module RD.Server.Cli.Opts (argParser) where

import Options.Applicative
import qualified Data.Text as T

import RD.Server.Config

parseBlockSize :: ReadM Integer
parseBlockSize = eitherReader $ \s ->
  let t = T.pack s
      upper = T.toUpper t
      parseNum x = case reads (T.unpack x) of
                     [(i, "")] | i > 0 -> Right i
                     _ -> Left "block size must be positive integer, example: 2M, 4M, 8M"
  in case T.unsnoc upper of
       Just (numTxt, 'M') -> fmap (\n -> n * 1024 * 1024) (parseNum numTxt)
       _ -> Left "invalid --block-size, only MiB suffix is supported, example: 2M"

argParser :: Parser RDConfig
argParser = RDConfig
  <$> strOption
      (  long "host"
      <> short 'h'
      <> help "http listen host"
      <> showDefault
      <> value "::"
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
  <*> option parseBlockSize
      (  long "block-size"
      <> help "download block size, supports MiB suffix, e.g. 2M, 4M, 8M. default is 2M."
      <> showDefault
      <> value 2097152
      <> metavar "SIZE" )
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
