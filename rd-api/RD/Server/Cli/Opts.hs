module RD.Server.Cli.Opts (argParser) where

import Options.Applicative

import RD.Server.Config

argParser :: Parser RDConfig
argParser = RDConfig
  <$> strOption
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
  <*> strOption
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
  <*> strOption
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
  <*> switch
      (  long "verbose"
      <> short 'v'
      <> help "show more debug message"
      <> showDefault )
  <*> switch
      (  long "version"
      <> short 'V'
      <> help "show program version and exit" )
