{-# LANGUAGE LambdaCase #-}

module Jikka.RestrictedPython.Util where

import Data.List (delete, nub)
import Jikka.Common.Alpha
import Jikka.RestrictedPython.Language.Expr

genType :: MonadAlpha m => m Type
genType = do
  i <- nextCounter
  return $ VarTy (TypeName ('$' : show i))

freeTyVars :: Type -> [TypeName]
freeTyVars = nub . go
  where
    go = \case
      VarTy x -> [x]
      IntTy -> []
      BoolTy -> []
      ListTy t -> go t
      TupleTy ts -> concat $ mapM go ts
      CallableTy ts ret -> concat $ mapM go (ret : ts)

freeVars :: Expr -> [VarName]
freeVars = nub . go
  where
    go = \case
      BoolOp e1 _ e2 -> go e1 ++ go e2
      BinOp e1 _ e2 -> go e1 ++ go e2
      UnaryOp _ e -> go e
      Lambda args e -> foldl (\vars (x, _) -> delete x vars) (go e) args
      IfExp e1 e2 e3 -> go e1 ++ go e2 ++ go e3
      ListComp e (Comprehension x iter pred) -> go iter ++ foldl (\vars x -> delete x vars) (go e ++ concatMap go pred) (targetVars x)
      Compare e1 _ e2 -> go e1 ++ go e2
      Call f args -> concatMap go (f : args)
      Constant _ -> []
      Subscript e1 e2 -> go e1 ++ go e2
      Name x -> [x]
      List _ es -> concatMap go es
      Tuple es -> concatMap go es
      SubscriptSlice e from to step -> go e ++ concatMap go from ++ concatMap go to ++ concatMap go step

freeVarsTarget :: Target -> [VarName]
freeVarsTarget = nub . go
  where
    go = \case
      SubscriptTrg _ e -> freeVars e
      NameTrg _ -> []
      TupleTrg xs -> concatMap go xs

targetVars :: Target -> [VarName]
targetVars = nub . go
  where
    go = \case
      SubscriptTrg x _ -> go x
      NameTrg x -> [x]
      TupleTrg xs -> concatMap go xs

hasNoSubscriptTrg :: Target -> Bool
hasNoSubscriptTrg = \case
  SubscriptTrg _ _ -> False
  NameTrg _ -> True
  TupleTrg xs -> all hasNoSubscriptTrg xs

-- | `hasNoSubscriptTrgInLoop` checks that there are no `SubscriptTrg` in loop counters of for-loops.
hasNoSubscriptionInLoopCounters :: Program -> Bool
hasNoSubscriptionInLoopCounters _ = True -- TODO

-- | `hasNoNameLeakFromForLoops ` checks that there are no leaks of loop counters of for-loops.
hasNoNameLeakOfLoopCounters :: Program -> Bool
hasNoNameLeakOfLoopCounters _ = True -- TODO
