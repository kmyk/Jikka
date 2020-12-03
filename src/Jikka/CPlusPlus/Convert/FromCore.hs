{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE LambdaCase #-}
{-# LANGUAGE OverloadedStrings #-}

-- |
-- Module      : Jikka.CPlusPlus.Convert.FromCore
-- Description : converts core exprs to C++ exprs.
-- Copyright   : (c) Kimiyuki Onaka, 2020
-- License     : Apache License 2.0
-- Maintainer  : kimiyuki95@gmail.com
-- Stability   : experimental
-- Portability : portable
--
-- `Jikka.Language.CPlusPlus.FromCore` converts exprs of our core language to exprs of C++.
module Jikka.CPlusPlus.Convert.FromCore
  ( run,
  )
where

import Control.Monad.Except
import Data.Char (isAlphaNum)
import qualified Jikka.CPlusPlus.Language.Expr as Y
import Jikka.Common.Alpha
import qualified Jikka.Common.Language.Name as X
import qualified Jikka.Core.Language.Beta as X
import qualified Jikka.Core.Language.BuiltinPatterns as X
import qualified Jikka.Core.Language.Expr as X
import qualified Jikka.Core.Language.Lint as X

--------------------------------------------------------------------------------
-- monad

newFreshName :: MonadAlpha m => String -> String -> m String
newFreshName base hint = do
  i <- nextCounter
  let suffix = case takeWhile (\c -> isAlphaNum c || c == '_') hint of
        "" -> ""
        hint' -> "_" ++ hint'
  return (base ++ show i ++ suffix)

renameVarName :: MonadAlpha m => String -> X.VarName -> m Y.VarName
renameVarName kind x = Y.VarName <$> newFreshName kind (X.unVarName x)

type Env = [(X.VarName, X.Type, Y.VarName)]

typecheckExpr :: MonadError String m => Env -> X.Expr -> m X.Type
typecheckExpr env = X.typecheckExpr (map (\(x, t, _) -> (x, t)) env)

lookupVarName :: MonadError String m => Env -> X.VarName -> m Y.VarName
lookupVarName env x = case lookup x (map (\(x, _, y) -> (x, y)) env) of
  Just y -> return y
  Nothing -> throwError $ "CodeGen Error: undefined variable: " ++ show x

--------------------------------------------------------------------------------
-- run

runType :: MonadError String m => X.Type -> m Y.Type
runType = \case
  X.IntTy -> return Y.TyInt64
  X.BoolTy -> return Y.TyBool
  X.ListTy t -> Y.TyVector <$> runType t
  t@X.FunTy {} -> throwError $ "CodeGen Error: function type appears at invalid place: " ++ show t

runLiteral :: MonadError String m => X.Literal -> m Y.Literal
runLiteral = \case
  X.LitBuiltin builtin -> throwError $ "CodeGen Error: cannot use builtin functaions as values: " ++ show builtin
  X.LitInt n -> return $ Y.LitInt64 n
  X.LitBool p -> return $ Y.LitBool p

runAppBuiltin :: MonadError String m => X.Builtin -> [Y.Expr] -> m Y.Expr
runAppBuiltin f args = case (f, args) of
  -- arithmetical functions
  (X.Negate, [e]) -> return $ Y.UnOp Y.Negate e
  (X.Plus, [e1, e2]) -> return $ Y.BinOp Y.Add e1 e2
  (X.Minus, [e1, e2]) -> return $ Y.BinOp Y.Sub e1 e2
  (X.Mult, [e1, e2]) -> return $ Y.BinOp Y.Mul e1 e2
  (X.FloorDiv, [e1, e2]) -> return $ Y.Call (Y.Function "jikka::floordiv" []) [e1, e2]
  (X.FloorMod, [e1, e2]) -> return $ Y.Call (Y.Function "jikka::floormod" []) [e1, e2]
  (X.CeilDiv, [e1, e2]) -> return $ Y.Call (Y.Function "jikka::ceildiv" []) [e1, e2]
  (X.CeilMod, [e1, e2]) -> return $ Y.Call (Y.Function "jikka::ceilmod" []) [e1, e2]
  (X.Pow, [e1, e2]) -> return $ Y.Call (Y.Function "jikka::pow" []) [e1, e2]
  -- induction functions
  (X.NatInd t, [base, step, n]) -> do
    t <- runType t
    return $ Y.Call (Y.Function "jikka::natind" [t]) [base, step, n]
  -- advanced arithmetical functions
  (X.Abs, [e]) -> return $ Y.Call (Y.Function "std::abs" []) [e]
  (X.Gcd, [e1, e2]) -> return $ Y.Call (Y.Function "std::gcd" []) [e1, e2]
  (X.Lcm, [e1, e2]) -> return $ Y.Call (Y.Function "std::lcm" []) [e1, e2]
  (X.Min, [e1, e2]) -> return $ Y.Call (Y.Function "std::min" []) [e1, e2]
  (X.Max, [e1, e2]) -> return $ Y.Call (Y.Function "std::max" []) [e1, e2]
  -- logical functions
  (X.Not, [e]) -> return $ Y.UnOp Y.Not e
  (X.And, [e1, e2]) -> return $ Y.BinOp Y.And e1 e2
  (X.Or, [e1, e2]) -> return $ Y.BinOp Y.Or e1 e2
  (X.Implies, [e1, e2]) -> return $ Y.BinOp Y.Or (Y.UnOp Y.Not e1) e2
  (X.If _, [e1, e2, e3]) -> return $ Y.Cond e1 e2 e3
  -- bitwise functions
  (X.BitNot, [e]) -> return $ Y.UnOp Y.BitNot e
  (X.BitAnd, [e1, e2]) -> return $ Y.BinOp Y.BitAnd e1 e2
  (X.BitOr, [e1, e2]) -> return $ Y.BinOp Y.BitOr e1 e2
  (X.BitXor, [e1, e2]) -> return $ Y.BinOp Y.BitXor e1 e2
  (X.BitLeftShift, [e1, e2]) -> return $ Y.BinOp Y.BitLeftShift e1 e2
  (X.BitRightShift, [e1, e2]) -> return $ Y.BinOp Y.BitRightShift e1 e2
  -- modular functions
  (X.Inv, [e1, e2]) -> return $ Y.Call (Y.Function "std::modinv" []) [e1, e2]
  (X.PowMod, [e1, e2, e3]) -> return $ Y.Call (Y.Function "std::modpow" []) [e1, e2, e3]
  -- list functions
  (X.Len _, [e]) -> return $ Y.Cast Y.TyInt64 (Y.Call (Y.Method e "size") [])
  (X.Tabulate t, [n, f]) -> do
    t <- runType t
    return $ Y.Call (Y.Function "jikka::tabulate" [t]) [n, f]
  (X.Map t1 t2, [f, xs]) -> do
    t1 <- runType t1
    t2 <- runType t2
    return $ Y.Call (Y.Function "jikka::map" [t1, t2]) [f, xs]
  (X.At _, [e1, e2]) -> return $ Y.At e1 e2
  (X.Sum, [e]) -> return $ Y.Call (Y.Function "jikka::sum" []) [e]
  (X.Product, [e]) -> return $ Y.Call (Y.Function "jikka::product" []) [e]
  (X.Min1, [e]) -> return $ Y.Call (Y.Function "jikka::minimum" []) [e]
  (X.Max1, [e]) -> return $ Y.Call (Y.Function "jikka::maximum" []) [e]
  (X.ArgMin, [e]) -> return $ Y.Call (Y.Function "jikka::argmin" []) [e]
  (X.ArgMax, [e]) -> return $ Y.Call (Y.Function "jikka::argmax" []) [e]
  (X.All, [e]) -> return $ Y.Call (Y.Function "jikka::all" []) [e]
  (X.Any, [e]) -> return $ Y.Call (Y.Function "jikka::any" []) [e]
  (X.Sorted t, [e]) -> do
    t <- runType t
    return $ Y.Call (Y.Function "jikka::sort" [t]) [e]
  (X.List _, [e]) -> return e
  (X.Reversed t, [e]) -> do
    t <- runType t
    return $ Y.Call (Y.Function "jikka::reverse" [t]) [e]
  (X.Range1, [e]) -> return $ Y.Call (Y.Function "jikka::range" []) [e]
  (X.Range2, [e1, e2]) -> return $ Y.Call (Y.Function "jikka::range" []) [e1, e2]
  (X.Range3, [e1, e2, e3]) -> return $ Y.Call (Y.Function "jikka::range" []) [e1, e2, e3]
  -- arithmetical relations
  (X.LessThan, [e1, e2]) -> return $ Y.BinOp Y.LessThan e1 e2
  (X.LessEqual, [e1, e2]) -> return $ Y.BinOp Y.LessEqual e1 e2
  (X.GreaterThan, [e1, e2]) -> return $ Y.BinOp Y.GreaterThan e1 e2
  (X.GreaterEqual, [e1, e2]) -> return $ Y.BinOp Y.GreaterEqual e1 e2
  -- equality relations (polymorphic)
  (X.Equal _, [e1, e2]) -> return $ Y.BinOp Y.Equal e1 e2
  (X.NotEqual _, [e1, e2]) -> return $ Y.BinOp Y.NotEqual e1 e2
  -- combinational functions
  (X.Fact, [e]) -> return $ Y.Call (Y.Function "jikka::fact" []) [e]
  (X.Choose, [e1, e2]) -> return $ Y.Call (Y.Function "jikka::choose" []) [e1, e2]
  (X.Permute, [e1, e2]) -> return $ Y.Call (Y.Function "jikka::permute" []) [e1, e2]
  (X.MultiChoose, [e1, e2]) -> return $ Y.Call (Y.Function "jikka::multiChoose" []) [e1, e2]
  _ -> throwError "CodeGen Error: invalid builtin call"

runExpr :: (MonadAlpha m, MonadError String m) => Env -> X.Expr -> m Y.Expr
runExpr env = \case
  X.Var x -> Y.Var <$> lookupVarName env x
  X.Lit lit -> Y.Lit <$> runLiteral lit
  X.App f args -> do
    args <- mapM (runExpr env) args
    case f of
      X.Lit (X.LitBuiltin builtin) -> runAppBuiltin builtin args
      e -> do
        e <- runExpr env e
        return $ Y.Call (Y.Callable e) args
  X.Lam args e -> do
    args <- forM args $ \(x, t) -> do
      y <- renameVarName "b" x
      return (x, t, y)
    let env' = reverse args ++ env
    args <- forM args $ \(_, t, y) -> do
      t <- runType t
      return (t, y)
    ret <- runType =<< typecheckExpr env' e
    body <- runExprToStatements env' e
    return $ Y.Lam args ret body
  X.Let x _ e1 e2 -> runExpr env $ X.substitute x e1 e2

runExprToStatements :: (MonadAlpha m, MonadError String m) => Env -> X.Expr -> m [Y.Statement]
runExprToStatements env = \case
  X.Let x t e1 e2 -> do
    y <- renameVarName "x" x
    t' <- runType t
    e1 <- runExpr env e1
    e2 <- runExprToStatements ((x, t, y) : env) e2
    return $ Y.Declare t' y (Just e1) : e2
  X.If' _ e1 e2 e3 -> do
    e1 <- runExpr env e1
    e2 <- runExprToStatements env e2
    e3 <- runExprToStatements env e3
    return [Y.If e1 e2 (Just e3)]
  e -> do
    e <- runExpr env e
    return [Y.Return e]

runToplevelFunDef :: (MonadAlpha m, MonadError String m) => Env -> Y.VarName -> [(X.VarName, X.Type)] -> X.Type -> X.Expr -> m [Y.ToplevelStatement]
runToplevelFunDef env f args ret body = do
  ret <- runType ret
  args <- forM args $ \(x, t) -> do
    y <- renameVarName "a" x
    return (x, t, y)
  body <- runExprToStatements (reverse args ++ env) body
  args <- forM args $ \(_, t, y) -> do
    t <- runType t
    return (t, y)
  return [Y.FunDef ret f args body]

runToplevelVarDef :: (MonadAlpha m, MonadError String m) => Env -> Y.VarName -> X.Type -> X.Expr -> m [Y.ToplevelStatement]
runToplevelVarDef env x t e = do
  t <- runType t
  e <- runExpr env e
  return [Y.VarDef t x e]

runToplevelExpr :: (MonadAlpha m, MonadError String m) => Env -> X.ToplevelExpr -> m [Y.ToplevelStatement]
runToplevelExpr env = \case
  X.ResultExpr e -> do
    t <- typecheckExpr env e
    case t of
      X.FunTy ts ret -> do
        let f = Y.VarName "solve"
        args <- forM ts $ \t -> do
          t <- runType t
          y <- Y.VarName <$> newFreshName "a" ""
          return (t, y)
        ret <- runType ret
        e <- runExpr env e
        let body = [Y.Return (Y.Call (Y.Callable e) (map (Y.Var . snd) args))]
        return [Y.FunDef ret f args body]
      _ -> runToplevelVarDef env (Y.VarName "ans") t e
  X.ToplevelLet rec f args ret body cont -> do
    g <- renameVarName "f" f
    let t = X.FunTy (map snd args) ret
    stmt <- case (rec, args) of
      (X.NonRec, []) -> runToplevelVarDef env g ret body
      (X.NonRec, _) -> runToplevelFunDef env g args ret body
      (X.Rec, _) -> runToplevelFunDef ((f, t, g) : env) g args ret body
    cont <- runToplevelExpr ((f, t, g) : env) cont
    return $ stmt ++ cont

runProgram :: (MonadAlpha m, MonadError String m) => X.Program -> m Y.Program
runProgram prog = Y.Program <$> runToplevelExpr [] prog

run :: X.Program -> Either String Y.Program
run = evalAlpha' . runProgram