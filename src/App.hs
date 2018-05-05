module App (app, waiApp) where

import Control.Monad.IO.Class (liftIO)

import Network.Wai (Application)
import Web.Scotty
import Data.Aeson (Value(..), toJSON, object, (.=))
import qualified Data.Text.Lazy as LT

import RD.Lib (sha1sum)

app :: ScottyM ()
app = do
  get (literal "/rd/") $ do
    json $ object [("ok" .= True)
                  ,("app" .= ("reliable-download api" :: String))]
  get (regex "^/rd/(.*)") $ do
    path :: LT.Text <- param "1"
    fullPath :: LT.Text <- param "0"
    json $ object [("ok" .= True)
                  ,("full_path" .= fullPath)
                  ,("path" .= path)]
  get "/rd/debug/t1" $ do
    sha1 <- liftIO $ sha1sum "/home/sylecn/persist/cache/ideaIC-2018.1.tar.gz"
    json $ object ["ok" .= True
                  ,"sha1sum" .= sha1]

waiApp :: IO Application
waiApp = scottyApp app
