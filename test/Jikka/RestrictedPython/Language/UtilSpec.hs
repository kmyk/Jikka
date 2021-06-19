{-# LANGUAGE OverloadedStrings #-}

module Jikka.RestrictedPython.Language.UtilSpec
  ( spec,
  )
where

import Jikka.RestrictedPython.Language.Expr
import Jikka.RestrictedPython.Language.Util
import Test.Hspec

spec :: Spec
spec = describe "doesAlwaysReturn" $ do
  it "works" $ do
    let stmt = AnnAssign (NameTrg "a") IntTy (Constant (ConstInt 0))
    let expected = False
    doesAlwaysReturn stmt `shouldBe` expected
  it "works'" $ do
    let stmt = Return (Name "a")
    let expected = True
    doesAlwaysReturn stmt `shouldBe` expected
  it "returns true for an if-statement which both branches always return" $ do
    let stmt =
          If
            (Constant (ConstBool True))
            [ AnnAssign (NameTrg "b") IntTy (Constant (ConstInt 0)),
              Return (Name "a"),
              AugAssign (NameTrg "b") Add (Name "1")
            ]
            [ Return (Constant (ConstInt 1))
            ]
    let expected = True
    doesAlwaysReturn stmt `shouldBe` expected
  it "returns false for for-statement" $ do
    let stmt = For (NameTrg "x") (List IntTy []) [Return (Constant (ConstInt 0))]
    let expected = False
    doesAlwaysReturn stmt `shouldBe` expected