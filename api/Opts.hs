module Opts (argParser) where

import Data.Semigroup ((<>))

import Options.Applicative

import Config

argParser :: Parser RDConfig
argParser = RDConfig
  <$> option auto
      (  long "host"
      <> short 'h'
      <> help "http listen host"
      <> showDefault
      <> value "0.0.0.0"
      <> metavar "HOST" )
  <*> option auto
      (  long "port"
      <> short 'p'
      <> help "http listen port"
      <> showDefault
      <> value 8082
      <> metavar "PORT" )
  <*> option auto
      (  long "redis-host"
      <> help "redis host"
      <> showDefault
      <> value "127.0.0.1"
      <> metavar "REDIS_HOST" )
  <*> option auto
      (  long "redis-port"
      <> help "redis port"
      <> showDefault
      <> value 6379
      <> metavar "REDIS_PORT" )
  <*> option auto
      (  long "web-root"
      <> short 'd'
      <> help "web root directory"
      <> showDefault
      <> value "."
      <> metavar "DIR" )
  <*> option auto
      (  long "worker"
      <> short 'w'
      <> help "how many concurrent workers to calculator sha1sum for file"
      <> showDefault
      <> value 2
      <> metavar "INT")
