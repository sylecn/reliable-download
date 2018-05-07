module Opts (RDOptions(..), argParser) where

import qualified Data.Text as T
import Data.Semigroup ((<>))

import Options.Applicative

data RDOptions = RDOptions
  { blockMaxRetry :: Int
  , keepBlockData :: Bool
  , tempDir :: FilePath
  , outputDir :: FilePath
  , workerCount :: Int
  , verbose :: Bool
  , urls :: [T.Text] } deriving (Show)

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
      (  long "verbose"
      <> short 'v'
      <> help "show more debug message"
      <> showDefault )
  <*> some (argument str (metavar "URL..."))
