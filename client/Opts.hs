module Opts (RDOptions(..), argParser, RDClientRuntimeConfig(..)) where

import qualified Data.Text as T

import Options.Applicative
import qualified System.Logger as L

data RDOptions = RDOptions
  { blockMaxRetry :: Int
  , keepBlockData :: Bool
  , rollingCombine :: Bool
  , tempDir :: FilePath
  , outputDir :: FilePath
  , workerCount :: Int
  , forceOverwrite :: Bool
  , verbose :: Bool
  , showVersion :: Bool
  , urls :: [T.Text] } deriving (Show)

data RDClientRuntimeConfig = RDClientRuntimeConfig
    { rdOptions :: RDOptions
    , rdLogger :: L.Logger }

argParser :: Parser RDOptions
argParser = RDOptions
  <$> option auto
      (  long "block-max-retry"
      <> short 'r'
      <> help "max retry times for each block"
      <> showDefault
      <> value 30
      <> metavar "INT" )
  <*> switch
      (  long "keep"
      <> short 'k'
      <> help "keep block data when download has finished and combined"
      <> showDefault )
  <*> switch
      (  long "rolling-combine"
      <> short 'l'
      <> help "delete each block data right after combine, conflict with --keep"
      <> showDefault )
  <*> strOption
      (  long "temp-dir"
      <> short 'd'
      <> help "the dir to keep block download data"
      <> showDefault
      <> value ".blocks"
      <> metavar "TEMP_DIR" )
  <*> strOption
      (  long "output-dir"
      <> short 'o'
      <> help "the dir to keep the final combined file"
      <> showDefault
      <> value "."
      <> metavar "OUTPUT_DIR" )
  <*> option auto
      (  long "worker"
      <> short 'w'
      <> help "concurrent HTTP download worker"
      <> showDefault
      <> value 5
      <> metavar "INT" )
  <*> switch
      (  long "force"
      <> short 'f'
      <> help "overwrite exiting target file in OUTPUT_DIR"
      <> showDefault )
  <*> switch
      (  long "verbose"
      <> short 'v'
      <> help "show more debug message"
      <> showDefault )
  <*> switch
      (  long "version"
      <> short 'V'
      <> help "show version number and exit" )
  <*> many (argument str (metavar "URL..."))
