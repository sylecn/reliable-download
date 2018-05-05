module Config where

import qualified Database.Redis as R

data RDConfig = RDConfig {
      host :: String
    , port :: Int
    , redisHost :: String
    , redisPort :: Int
    , webRoot :: FilePath
    } deriving (Show)

data RDRuntimeConfig = RDRuntimeConfig {
      config :: RDConfig
    , redisConn :: R.Connection
    }

defaultRDConfig :: RDConfig
defaultRDConfig = RDConfig {
                    host = "0.0.0.0"
                  , port = 8082
                  , redisHost = "127.0.0.1"
                  , redisPort = 6379
                  , webRoot = "/nonexistent"
                  }
