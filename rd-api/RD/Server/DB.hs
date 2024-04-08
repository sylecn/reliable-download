module RD.Server.DB where

import qualified Data.Text as T
import qualified Data.ByteString as B
import qualified Database.Redis as R

import RD.Utils
import RD.Server.Config

-- | insert a key value to db, if key does not exist in db.
insertIfNotExist :: RDRuntimeConfig -> B.ByteString -> B.ByteString -> IO (Either T.Text Bool)
insertIfNotExist rc key value = do
  redisReply <- R.runRedis (rcRedisConn rc) $ R.setnx key value
  case redisReply of
    Left reply -> do
      errorl rc $ "redis setnx " <> decodeUtf8 key <> " failed:\n\t" <> showt reply
      return $ Left "insertIfNotExist on DB failed"
    Right v -> return $ Right v

get :: RDRuntimeConfig -> B.ByteString -> IO (Either T.Text (Maybe B.ByteString))
get rc key = do
  redisReply <- R.runRedis (rcRedisConn rc) $ R.get key
  case redisReply of
    Left reply -> do
      let msg = "redis get " <> decodeUtf8 key <> " failed: " <> showt reply
      errorl rc msg
      return $ Left msg
    Right v -> return $ Right v

set :: RDRuntimeConfig -> B.ByteString -> B.ByteString -> IO (Either T.Text R.Status)
set rc key value = do
  redisReply <- R.runRedis (rcRedisConn rc) $ R.set key value
  case redisReply of
    Left reply -> do
      let msg = "redis set " <> decodeUtf8 key <> " to " <> decodeUtf8 value <> " failed: " <> showt reply
      errorl rc msg
      return $ Left msg
    Right v -> return $ Right v
