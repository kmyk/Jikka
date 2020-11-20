module Jikka.Converter.Python.Convert (run) where

import Control.Monad.Except
import Control.Monad.State.Strict
import Data.List (lookup)
import qualified Data.Set as S
import qualified Data.Map.Strict as M
import Jikka.Language.Common.Name
import Jikka.Language.Common.Pos
import qualified Jikka.Language.Python.Parsed.Type as X
import qualified Jikka.Language.Python.Parsed.Stdlib as X
import qualified Jikka.Language.Python.Typed.Type as Y
import qualified Jikka.Language.Python.Typed.Stdlib as Y

--------------------------------------------------------------------------------
-- prepare a monad

data ConvState
  = ConvState
      { nextId :: Int,
        funenv :: [(FunName, ([Y.Type], Y.Type))]
      }
  deriving (Eq, Ord, Show, Read)

type Conv a = ExceptT String (State ConvState) a

initialState :: ConvState
initialState =
  ConvState
    { nextId = 0,
      funenv = []
    }

runConv :: Conv a -> Either String a
runConv a = evalState (runExceptT a) initialState

--------------------------------------------------------------------------------
-- prepare utilities about names

genTypeName :: Conv TypeName
genTypeName = do
  id <- gets nextId
  modify $ \state -> state {nextId = id + 1}
  return $ "'u@" ++ show id

genType :: Conv Y.Type
genType = Y.Var <$> genTypeName

lookupFun :: FunName -> Conv (Maybe ([Y.Type], Y.Type))
lookupFun name = do
  funenv' <- gets funenv
  return $ M.lookup name funenv'

declareFun :: FunName -> [Y.Type] -> Y.Type -> Conv ()
declareFun name ts ret = modify $ \state -> state { funenv = (name, (ts, ret)) : funenv state }


-- ---------------------------------------------------------------------------
-- convert AST

convertType :: X.Type' -> Conv Y.Type
convertType t = case t of
  X.TyInt -> return Y.ATyInt
  X.TyNat -> return Y.ATyNat
  X.TyInterval l r -> Y.ATyInterval <$> convertExpr l <*> convertExpr r
  X.TyBool -> return Y.ATyBool
  X.TyList t -> Y.ATyList <$> convertType t
  X.TyIterator t -> Y.ATyIterator <$> convertType t
  X.TyArray t n -> Y.ATyArray <$> convertType t <*> convertExpr n

convertMaybeType :: Maybe X.Type' -> Conv Y.Type
convertMaybeType Nothing = genType
convertMaybeType (Just t) = convertType t

convertLiteral :: X.Literal -> Y.Literal
convertLiteral lit = case lit of
  X.LitInt n -> Y.LitInt n
  X.LitBool p -> Y.LitInt p

convertCall :: FunName -> [X.Expr'] -> Conv Y.Expr
convertCall name args = do
  args' <- mapM convertExpr args
  let args'' = map fst args'
  funtyp <- lookupFun name
  case funtyp of
    Just (ts, _) ->
     if length ts == length args''
         then return $ Y.Call name args''
         else Left $ "Type Error: the wrong number of arguments are given for function: " ++ show (unFunName name)
    Nothing -> case args'' of
        [e1] -> case (M.lookup name X.unaryOps, M.lookup name X.genericUnaryOps) of
            (op, _) -> return $ Y.UnOp op e1
            (_, op) -> do
              t <- toChurchType <$> genType
              return Y.UnOp (op t) e1
            _ -> Left $ "Internal Error: undefined function: " ++ show (unFunName name)
        [e1, e2] -> case (M.lookup name X.binaryOps, M.lookup name X.genericBinaryOps) of
            (op, _) -> return $ Y.BinOp op e1 e2
            (_, op) -> do
              t <- toChurchType <$> genType
              return $ Y.BinOp (op t) e1 e2
            _ -> Left $ "Internal Error: undefined function: " ++ show (unFunName name)
        [e1, e2, e3] -> case M.lookup name X.ternaryOps of
            op -> return $ Y.TerOp e1 e2 e3
            _ -> Left $ "Internal Error: undefined function: " ++ show (unFunName name)
        _ -> Left $ "Internal Error: undefined function: " ++ show (unFunName name)

convertExpr :: X.Expr' -> Conv Y.Expr
convertExpr e = case e of
  X.Lit lit -> return $ Y.Lit lit
  X.Var name -> return $ Y.Var name
  X.Sub e1 e2 -> do
    t <- toChurchType <$> genType
    return $ Y.BinOp (At t) e1 e2
  X.ListComp e1 name e2 e3 -> case name of
    Nothing -> Left "Internal Error: underscores are already removed at the alpah conversion"
    Just name -> do
        e2 <- convertExpr e2
        t <- genType
        withVar name t $ do
            e3 <- case e3 of
                Nothing -> return Nothing
                Just e3 -> Just <$> convertExpr e3
            e1 <- convertExpr e1
            return $ Y.ListComp e1 name e2 e3
  X.ListExt es -> Y.ListExt <$> mapM convertExpr es
  X.Call name args -> convertCall name args
  X.Cond e1 e2 e3 -> do
    t <- toChurchType <$> genType
    Y.TerOp (Y.Cond t) <*> convertExpr e1 <*> convertExpr e2 <*> convertExpr e3

convertListShape :: X.ListShape -> Conv [Y.Expr]
convertListShape shape = case shape of
  X.NoneShape -> return []
  X.ListShape shape e -> (:) <$> convertExpr e <*> convertListShape shape

convertSentence :: X.Sentence' -> Conv Y.Sentence
convertSentence sentence = case sentence of
  X.If e body1 body2 -> do
    e <- convertExpr e
    body1 <- mapM convertSentence body1
    body2 <- mapM convertSentence body2
    return $ Y.If e body1 body2
  X.For name e body -> do
    t <- genType
    e <- convertExpr e
    body <- mapM convertSentence body
    return $ Y.For name t e body
  X.Define name t e -> do
    t <- convertMaybeType
    e <- convertExpr e
    return $ Y.Define name t e
  X.Declare name t shape -> do
    t <- convertMaybeType
    shape <- convertShape shape
    return $ Y.Declare name t shape
  X.Assign name es e -> do
    es <- mapM convertExpr es
    e <- convertExpr e
    return $ Y.Assign name es e
  X.Assert e -> Y.Assert <$> convertExpr e
  X.Return e -> Y.Return <$> convertExpr e

convertToplevelDecl :: X.ToplevelDecl' -> Conv [Y.ToplevelDecl]
convertToplevelDecl decl = case decl of
  X.ConstDef name t e -> do
    t <- convertMaybeType t
    e <- convertExpr e
    return [Y.ConstDef name t e]
  X.FunDef name args ret body -> do
    args <- mapM (\(x, t) -> (,) x <$> convertMaybeType t) args
    ret <- convertMaybeType ret
    body <- mapM convertSentence body
    return [Y.FunDef name args ret body]
  X.FromImport path -> return []

run :: X.Program -> Either String Y.Program
run prog = runConv $ do
  let decls = X.decls prog
  decls <- mapM convertToplevelDecl decls
  return $ Y.Program (concat decls)
