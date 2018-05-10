module TestEither (spec) where

import qualified Data.Text as T

import Test.Hspec

step1 :: Either T.Text String
step1 = Left "step1 failed"

step2 :: Either T.Text String
step2 = Right "step2 ok"

step3 :: Either T.Text String
step3 = Right "step3 ok"

test1 :: Either T.Text String
test1 = do
  _ <- step1
  _ <- step2
  step3

test2 :: Either T.Text Int
test2 = do
  _ <- Left "err1"
  _ <- Right (2 :: Int)
  _ <- Right (3 :: Int)
  Right (5 :: Int)

test3 :: Either T.Text Int
test3 = do
  _ <- Right (2 :: Int)
  _ <- Right (3 :: Int)
  Right (5 :: Int)

two :: Either T.Text Int
two = Right 2

negtwo :: Either T.Text Int
negtwo = Right (-2)

inc :: Int -> Either T.Text Int
inc v = if v < 0 then
             Left "I don't work on negative value"
         else
             Right $ v + 1

incBy :: Int -> Int -> Either T.Text Int
incBy i v = if v < 0 then
             Left "I don't work on negative value"
         else
             Right $ v + i

test4 :: Either T.Text Int
test4 = do
  i <- two
  j <- inc i
  incBy 5 j


test5 :: Either T.Text Int
test5 = do
  i <- negtwo
  inc i

spec :: Spec
spec = do
  describe "either" $ do
    it "should be that" $ do
      test1 `shouldBe` step1
      test2 `shouldBe` Left "err1"
      test3 `shouldBe` Right (5 :: Int)
      test4 `shouldBe` Right (8 :: Int)
      test5 `shouldBe` Left "I don't work on negative value"
