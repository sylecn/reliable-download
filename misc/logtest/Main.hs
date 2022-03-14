-- The ReaderT Design Pattern
-- https://www.fpcomplete.com/blog/2017/06/readert-design-pattern/

module Main (main) where

import Control.Monad.Trans.Reader

import qualified System.Logger as L

data LogTestOptions = LogTestOptions
    { verbose :: Bool
    , workerCount :: Int } deriving (Show)

data LogTestRuntimeConfig = LogTestRuntimeConfig
                          { logTestOptions :: LogTestOptions
                          , logTestLogger :: L.Logger }

type LogTestApp = ReaderT LogTestRuntimeConfig IO

parseConfig :: IO LogTestRuntimeConfig
parseConfig = do
  let logSettings = (L.setFormat (Just "%Y-%0m-%0dT%0H:%0M:%0S") .
                     L.setLogLevel L.Info .
                     L.setDelimiter "  ")
                    L.defSettings
  logger <- L.new logSettings
  return LogTestRuntimeConfig
             { logTestOptions=LogTestOptions
                                 { verbose=True
                                 , workerCount=2}
             , logTestLogger=logger}

step1 :: LogTestApp ()
step1 = do
  rc <- ask
  let logger = logTestLogger rc
  L.info logger $ L.msg $ L.val "Running step1.1"
  L.info logger $ L.msg $ L.val "Running step1.2"
  L.flush logger

step2 :: LogTestApp ()
step2 = do
  rc <- ask
  let logger = logTestLogger rc
  L.info logger $ L.msg $ L.val "Running step2"
  L.flush logger

main :: IO ()
main = do
  rc <- parseConfig
  runReaderT
    (do
      step1
      step2)
    rc
