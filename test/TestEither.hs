module TestEither (spec) where

import qualified Data.Text as T

import Test.Hspec

test1 :: Either T.Text String
test1 = Left "test1 failed"

test2 :: Either T.Text String
test2 = Right "test2 ok"

test3 :: Either T.Text String
test3 = Right "test3 ok"

test :: Either T.Text String
test = do
  _ <- test1
  _ <- test2
  test3

spec :: Spec
spec = do
  describe "either" $ do
    it "should be that" $ do
      test `shouldBe` test1
