module App (mkApp, mkWaiApp) where

import Control.Monad.IO.Class (liftIO)

import Network.Wai (Application)
import Web.Scotty
import Data.Aeson (Value(..), toJSON, object, (.=))
import Data.Either (fromRight)

import qualified Data.Text.Lazy as LT
import qualified Database.Redis as R

import RD.Lib (sha1sum)

-- | given a redis connection pool, return a Scotty app.
mkApp :: R.Connection -> ScottyM ()
mkApp conn = do
  get (literal "/rd/") $ do
    json $ object [("ok" .= True)
                  ,("app" .= ("reliable-download api" :: String))]
  get (regex "^/rd/(.*)") $ do
    path :: LT.Text <- param "1"
    fullPath :: LT.Text <- param "0"
    json $ object [("ok" .= True)
                  ,("full_path" .= fullPath)
                  ,("path" .= path)]
  get "/debug/t1" $ do
    sha1 <- liftIO $ sha1sum "/home/sylecn/persist/cache/ideaIC-2018.1.tar.gz"
    json $ object ["ok" .= True
                  ,"sha1sum" .= sha1]
  get "/debug/count" $ do
    count <- liftIO $ R.runRedis conn $ do
                        count <- R.incr "count"
                        return count
    json $ object ["ok" .= True
                  ,"count" .= fromRight 0 count]

-- | given a redis connection pool, return a WAI app.
mkWaiApp :: R.Connection -> IO Application
mkWaiApp conn = scottyApp (mkApp conn)
