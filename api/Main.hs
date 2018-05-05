module Main (main) where

import Web.Scotty
import qualified Database.Redis as R

import App (mkApp)

main :: IO ()
main = do
  conn <- R.checkedConnect R.defaultConnectInfo
  putStrLn "listening on 0.0.0.0:8082"
  scotty 8082 $ mkApp conn
