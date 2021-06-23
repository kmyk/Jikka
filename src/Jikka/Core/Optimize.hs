{-# LANGUAGE FlexibleContexts #-}

-- |
-- Module      : Jikka.Core.Optimize
-- Description : is a meta module to combine other optimizers.
-- Copyright   : (c) Kimiyuki Onaka, 2020
-- License     : Apache License 2.0
-- Maintainer  : kimiyuki95@gmail.com
-- Stability   : experimental
-- Portability : portable
--
-- `Jikka.Core.Optimize` is a module to combine other all optimizers.
module Jikka.Core.Optimize
  ( run,
  )
where

import Jikka.Common.Alpha
import Jikka.Common.Error
import qualified Jikka.Core.Convert.ANormal as ANormal
import qualified Jikka.Core.Convert.Alpha as Alpha
import qualified Jikka.Core.Convert.ConstantPropagation as ConstantPropagation
import qualified Jikka.Core.Convert.PropagateMod as PropagateMod
import qualified Jikka.Core.Convert.RemoveUnusedVars as RemoveUnusedVars
import qualified Jikka.Core.Convert.StrengthReduction as StrengthReduction
import qualified Jikka.Core.Convert.TrivialLetElimination as TrivialLetElimination
import qualified Jikka.Core.Convert.TypeInfer as TypeInfer
import Jikka.Core.Language.Expr

run :: (MonadAlpha m, MonadError Error m) => Program -> m Program
run prog = do
  prog <- Alpha.run prog
  prog <- TypeInfer.run prog
  prog <- RemoveUnusedVars.run prog
  prog <- ANormal.run prog
  prog <- TrivialLetElimination.run prog
  prog <- PropagateMod.run prog
  prog <- ConstantPropagation.run prog
  StrengthReduction.run prog
