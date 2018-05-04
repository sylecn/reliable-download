{-# LANGUAGE OverloadedStrings #-}

module Main (main) where

import Control.Monad.IO.Class (liftIO)
import GHC.Exts (fromList)

import Web.Scotty
import Data.Aeson (Value(..), toJSON, object, (.=))

import RD.Lib (sha1sum)

main :: IO ()
main = scotty 8082 $ do
  get "/" $ do
    json $ Object $ fromList [("ok", Bool True)
                             ,("app", "reliable-download api")]
  get "/debug/t1" $ do
    sha1 <- liftIO $ sha1sum "/home/sylecn/persist/cache/ideaIC-2018.1.tar.gz"
    json $ object ["ok" .= True
                  ,"sha1sum" .= sha1]
  get "/:word" $ do
    beam <- param "word"
    sha1 <- liftIO $ sha1sum beam
    html $ mconcat ["sha1sum for ", beam, " is ", sha1, "."]
