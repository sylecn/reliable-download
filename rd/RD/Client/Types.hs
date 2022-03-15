module RD.Client.Types where

import Control.Concurrent.MVar
import qualified Data.Text as T

import qualified System.Logger as L

-- | command line options
data RDOptions = RDOptions
  { blockMaxRetry :: Int
  , keepBlockData :: Bool
  , rollingCombine :: Bool
  , tempDir :: FilePath
  , outputDir :: FilePath
  , workerCount :: Int
  , forceOverwrite :: Bool
  , progressInterval :: Int    -- in seconds
  , verbose :: Bool
  , showVersion :: Bool
  , urls :: [T.Text] } deriving (Show)

-- | track DL progress in client side
data Progress = Progress {
      piTotalFileCount :: Int
    , piDownloadedFileCount :: Int
    , piTotalBlockCount :: Int    -- overall block count, for all URLs
    , piDownloadedBlockCount :: Int  -- overall DL block count
    , piCurrentFileName :: T.Text
    , piCurrentFileTotalBlockCount :: Int
    , piCurrentFileDownloadedBlockCount :: Int
    } deriving (Show)

-- | app runtime config, passed all over the functions
data RDClientRuntimeConfig = RDClientRuntimeConfig
    { rdOptions :: RDOptions
    , rdLogger :: L.Logger
    , rdProgress :: MVar Progress}
