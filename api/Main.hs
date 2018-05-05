module Main (main) where

import Web.Scotty

import App (app)

main :: IO ()
main = do
  putStrLn "listening on 0.0.0.0:8082"
  scotty 8082 app
