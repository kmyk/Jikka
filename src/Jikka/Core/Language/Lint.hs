{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE LambdaCase #-}

-- |
-- Module      : Jikka.Core.Language.Lint
-- Description : checks the invariants (e.g. types) of data types of our core language.
-- Copyright   : (c) Kimiyuki Onaka, 2020
-- License     : Apache License 2.0
-- Maintainer  : kimiyuki95@gmail.com
-- Stability   : experimental
-- Portability : portable
--
-- `Jikka.Core.Language.Lint` module checks the invariants of data types. Mainly, this checks types of `Expr`.
module Jikka.Core.Language.Lint where

import Control.Monad.Except
import Jikka.Common.Language.Name
import Jikka.Core.Language.Expr

builtinToType :: Builtin -> Type
builtinToType = \case
  -- arithmetical functions
  Negate -> Fun1Ty IntTy
  Plus -> Fun2Ty IntTy
  Minus -> Fun2Ty IntTy
  Mult -> Fun2Ty IntTy
  FloorDiv -> Fun2Ty IntTy
  FloorMod -> Fun2Ty IntTy
  CeilDiv -> Fun2Ty IntTy
  CeilMod -> Fun2Ty IntTy
  Pow -> Fun2Ty IntTy
  -- induction functions
  NatInd t -> FunTy [t, FunTy [IntTy, t] t, IntTy] t
  -- advanced arithmetical functions
  Abs -> Fun1Ty IntTy
  Gcd -> Fun2Ty IntTy
  Lcm -> Fun2Ty IntTy
  Min -> Fun2Ty IntTy
  Max -> Fun2Ty IntTy
  -- logical functions
  Not -> Fun1Ty BoolTy
  And -> Fun2Ty BoolTy
  Or -> Fun2Ty BoolTy
  Implies -> Fun2Ty BoolTy
  If t -> FunTy [BoolTy, t, t] t
  -- bitwise functions
  BitNot -> Fun1Ty IntTy
  BitAnd -> Fun2Ty IntTy
  BitOr -> Fun2Ty IntTy
  BitXor -> Fun2Ty IntTy
  BitLeftShift -> Fun2Ty IntTy
  BitRightShift -> Fun2Ty IntTy
  -- modular functions
  Inv -> Fun2Ty IntTy
  PowMod -> Fun3Ty IntTy
  -- list functions
  Len t -> FunTy [ListTy t] IntTy
  Tabulate t -> FunTy [IntTy, FunTy [IntTy] t] (ListTy t)
  Map t1 t2 -> FunTy [FunTy [t1] t2, ListTy t1] (ListTy t2)
  At t -> FunTy [ListTy t, IntTy] t
  Sum -> FunLTy IntTy
  Product -> FunLTy IntTy
  Min1 -> FunLTy IntTy
  Max1 -> FunLTy IntTy
  ArgMin -> FunLTy IntTy
  ArgMax -> FunLTy IntTy
  All -> FunLTy BoolTy
  Any -> FunLTy BoolTy
  Sorted t -> Fun1Ty (ListTy t)
  List t -> Fun1Ty (ListTy t)
  Reversed t -> Fun1Ty (ListTy t)
  Range1 -> FunTy [IntTy] (ListTy IntTy)
  Range2 -> FunTy [IntTy, IntTy] (ListTy IntTy)
  Range3 -> FunTy [IntTy, IntTy, IntTy] (ListTy IntTy)
  -- arithmetical relations
  LessThan -> FunTy [IntTy, IntTy] BoolTy
  LessEqual -> FunTy [IntTy, IntTy] BoolTy
  GreaterThan -> FunTy [IntTy, IntTy] BoolTy
  GreaterEqual -> FunTy [IntTy, IntTy] BoolTy
  -- equality relations (polymorphic)
  Equal t -> FunTy [t, t] BoolTy
  NotEqual t -> FunTy [t, t] BoolTy
  -- combinational functions
  Fact -> Fun1Ty IntTy
  Choose -> Fun2Ty IntTy
  Permute -> Fun2Ty IntTy
  MultiChoose -> Fun2Ty IntTy

literalToType :: Literal -> Type
literalToType = \case
  LitBuiltin builtin -> builtinToType builtin
  LitInt _ -> IntTy
  LitBool _ -> BoolTy

type TypeEnv = [(VarName, Type)]

-- | `typecheckExpr` checks that the given `Expr` has the correct types.
typecheckExpr :: MonadError String m => TypeEnv -> Expr -> m Type
typecheckExpr env = \case
  Var x -> case lookup x env of
    Nothing -> throwError $ "Internal Error: undefined variable: " ++ show (unVarName x)
    Just t -> return t
  Lit lit -> return $ literalToType lit
  App e args -> do
    t <- typecheckExpr env e
    ts <- mapM (typecheckExpr env) args
    case t of
      FunTy ts' ret | ts' == ts -> return ret
      _ -> throwError $ "Internal Error: invalid funcall: " ++ show (App e args, t, ts)
  Lam args e -> FunTy (map snd args) <$> typecheckExpr (reverse args ++ env) e
  Let x t e1 e2 -> do
    t' <- typecheckExpr env e1
    if t == t'
      then typecheckExpr ((x, t) : env) e2
      else throwError $ "Internal Error: wrong type binding: " ++ show (Let x t e1 e2)

typecheckToplevelExpr :: MonadError String m => TypeEnv -> ToplevelExpr -> m Type
typecheckToplevelExpr env = \case
  ResultExpr e -> typecheckExpr env e
  ToplevelLet rec x args ret body cont -> do
    let t = case args of
          [] -> ret
          _ -> FunTy (map snd args) ret
    ret' <- case rec of
      NonRec -> typecheckExpr (reverse args ++ env) body
      Rec -> typecheckExpr (reverse args ++ (x, t) : env) body
    if ret' == ret then return () else throwError "Internal Error: returned type is not corrent"
    typecheckToplevelExpr ((x, t) : env) cont

typecheckProgram :: MonadError String m => Program -> m Type
typecheckProgram = typecheckToplevelExpr []

typecheckProgram' :: MonadError String m => Program -> m Program
typecheckProgram' prog = do
  typecheckProgram prog
  return prog