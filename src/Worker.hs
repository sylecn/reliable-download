module Worker (startWorkers, sha1sumFileRange, fileRange) where

import Control.Concurrent.Chan
import System.IO (IOMode(ReadMode), withBinaryFile)
import GHC.IO.Handle (Handle, hTell, hSeek, SeekMode(AbsoluteSeek))
import Control.Monad (when, replicateM_)
import Data.Monoid ((<>))
import Control.Concurrent (forkIO)
import qualified Data.ByteString as B
import qualified Data.ByteString.Lazy as LB

import qualified Database.Redis as R

import Type
import Config
import RD.Lib (sha1sumOnBytes)

-- | read file range data as LB.ByteString. handle must be a handle to an
-- opened file.
fileRangeH :: Handle -> Integer -> Integer -> IO LB.ByteString
fileRangeH handle start end = do
  pos <- hTell handle
  when (pos /= start) $ hSeek handle AbsoluteSeek start
  LB.hGet handle $ fromIntegral (end - start + 1)

-- | get file content in given range as IO LB.ByteString
fileRange :: FilePath -> Integer -> Integer -> IO LB.ByteString
fileRange filepath start end =
  withBinaryFile filepath ReadMode $ \handle ->
    fileRangeH handle start end

-- | calculate sha1sum for bytes in given file's byte range. start and end is
-- inclusive. This is only used in tests.
sha1sumFileRange :: FilePath -> Integer -> Integer -> IO LB.ByteString
sha1sumFileRange filepath start end = fmap sha1sumOnBytes $ fileRange filepath start end

-- | a file worker fetch FillBlockParam from fileChan, then calculate sha1sum
-- for all blocks and write result to redis. then mark the file as done.
fileWorker :: RDRuntimeConfig -> IO ()
fileWorker runtimeConfig = do
  fbp <- readChan (fileChan runtimeConfig)
  let filepath = fbpFilepath fbp
      conn = redisConn runtimeConfig
  -- calculate sha1sum for each block and write result to redis hash
  results <- withBinaryFile filepath ReadMode $ \handle -> do
    let hashKey = blockSha1sumHashKey fbp
    mapM (calculateSha1ForBlock conn hashKey handle) (fbpBlocks fbp)
  let resultStatus = if and results then "done" else "error"
  redisReply <- R.runRedis conn $ R.set (fileStatusKey fbp) resultStatus
  case redisReply of
    Left reply -> do
      putStrLn $ "set file status failed: " <> show reply
    Right _ -> do
      putStrLn $ "set file status to " <> show resultStatus <> " for " <> filepath
      putStrLn $ "file handling done for " <> filepath
  return ()
    where
      -- | calculate sha1 for a single block. return IO True on success.
      calculateSha1ForBlock :: R.Connection -> B.ByteString -> Handle -> Block -> IO Bool
      calculateSha1ForBlock conn hashKey handle (blockId, start, end) = do
        redisReply <- R.runRedis conn $ R.hget hashKey (blockIdKey blockId)
        case redisReply of
          Left reply -> do
            putStrLn $ "redis hget failed on " <> show hashKey <> ": " <> show reply
            return False
          Right sha1sumMaybe ->
            case sha1sumMaybe of
              Just sha1sum -> do
                putStrLn $ "skip calculated block " <> show blockId
                return True
              Nothing -> do
                blockContent <- fileRangeH handle start end
                let blockSha1 = LB.toStrict $ sha1sumOnBytes blockContent
                redisReply <- R.runRedis conn $ R.hset hashKey (blockIdKey blockId) blockSha1
                case redisReply of
                  Left reply -> do
                    putStrLn $ "redis hset failed on " <> show hashKey <> ": " <> show reply
                    return False
                  Right bool ->
                    if bool then
                      do
                        putStrLn $ "redis hset " <> show hashKey <> " " <> show blockId <> " ok"
                        return True
                     else
                        return False

startWorkers :: RDRuntimeConfig -> IO ()
startWorkers runtimeConfig = do
  let workerCount = fileWorkerCount $ config runtimeConfig
  putStrLn $ "creating " <> show workerCount <> " file worker(s)"
  replicateM_ workerCount (forkIO $ fileWorker runtimeConfig)
