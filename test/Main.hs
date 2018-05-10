module Main (main) where

import Test.Hspec

import qualified TestApi
import qualified TestEither

main :: IO ()
main = do
  hspec TestApi.spec
  hspec TestApi.apiSpec
  hspec TestEither.spec
