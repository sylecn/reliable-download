module TestApi
    ( spec
    , apiSpec ) where

-- GET /rd/some_complicated_url_safe_text

import Test.Hspec
import Test.Hspec.Wai
import Network.Wai.Test
import Network.HTTP.Types (status200, encodePathSegments, decodePathSegments)
import Data.Binary.Builder (toLazyByteString)
import Network.Wai (Application)
import System.FilePath
import System.Directory (removeFile)

import qualified Data.Aeson as J
import qualified Data.ByteString.Lazy as LB
import qualified Data.Text as T
import qualified Data.HashMap.Strict as H

import Config
import Lib (sha1sumOnBytes, guessFilename, genBlocks, humanReadableSize)
import Worker (fileRange, sha1sumFileRange)
import App (mkWaiApp)

-- | decode response as json object.
jsonObject :: SResponse -> Maybe J.Object
jsonObject resp = J.decode $ simpleBody resp

-- | decode response as json object, then retrieve a key.
jsonKey :: SResponse -> T.Text -> Maybe J.Value
jsonKey resp key = do
  m <- jsonObject resp
  H.lookup key m

jsonKeyAsBool :: SResponse -> T.Text -> Maybe Bool
jsonKeyAsBool resp key = do
  v <- jsonKey resp key
  case v of
    J.Bool b -> Just b
    _ -> Nothing

jsonKeyAsText :: SResponse -> T.Text -> Maybe T.Text
jsonKeyAsText resp key = do
  v <- jsonKey resp key
  case v of
    J.String b -> Just b
    _ -> Nothing

spec :: Spec
spec = do
  describe "dumb" $ do
    it "should be that" $ do
      True `shouldBe` True

  describe "3rd party libs" $ do

    it "should encode and decode utf-8 characters in URL" $ do
      (decodePathSegments . LB.toStrict . toLazyByteString . encodePathSegments) ["中文1", "路径2"] `shouldBe` ["中文1", "路径2"]

    it "should combine dir and relative file path correctly" $ do
      combine "/var/www/foo" "t1" `shouldBe` "/var/www/foo/t1"
      combine "/var/www/foo" "t1/t2" `shouldBe` "/var/www/foo/t1/t2"
      combine "/var/www/foo/" "t1" `shouldBe` "/var/www/foo/t1"
      combine "/var/www/foo/" "t1/t2" `shouldBe` "/var/www/foo/t1/t2"

  describe "appendFile" $ do
    it "should create file if file doesn't exist" $ do
      contentLB <- liftIO $ do
         LB.appendFile "/home/sylecn/d/t2.out" "abc"
         LB.appendFile "/home/sylecn/d/t2.out" "def"
         result <- LB.readFile "/home/sylecn/d/t2.out"
         removeFile "/home/sylecn/d/t2.out"
         return result
      contentLB `shouldBe` "abcdef"

  describe "humanReadableSize" $ do
    it "should work" $ do
      humanReadableSize 123 `shouldBe` "0.0 MiB"
      humanReadableSize 1048576 `shouldBe` "1.0 MiB"
      humanReadableSize 1048579 `shouldBe` "1.0 MiB"
      humanReadableSize (1048576 * 2) `shouldBe` "2.0 MiB"
      humanReadableSize 1572864 `shouldBe` "1.5 MiB"
      humanReadableSize 1572865 `shouldBe` "1.5 MiB"

  describe "sha1sumOnBytes" $ do
    it "should work" $ do
      sha1sumOnBytes "\n" `shouldBe` "adc83b19e793491b1c6ea0fd8b46cd9f32e592fc"
      sha1sumOnBytes "abcd" `shouldBe` "81fe8bfe87576c3ecb22426f8e57847382917acf"

  describe "genBlocks" $ do
    it "should work" $ do
      genBlocks 0 2 `shouldBe` []
      genBlocks 1 2 `shouldBe` [(0, 0, 0)]
      genBlocks 2 2 `shouldBe` [(0, 0, 1)]
      genBlocks 3 2 `shouldBe` [(0, 0, 1), (1, 2, 2)]
      genBlocks 4 2 `shouldBe` [(0, 0, 1), (1, 2, 3)]
      genBlocks 5 2 `shouldBe` [(0, 0, 1), (1, 2, 3), (2, 4, 4)]

  describe "guessFilename" $ do
    it "should work" $ do
      guessFilename "/abc.txt" `shouldBe` "abc.txt"
      guessFilename "foo/abc.txt" `shouldBe` "abc.txt"
      guessFilename "http://example.com/abc.txt" `shouldBe` "abc.txt"
      guessFilename "http://example.com/foo/abc.txt" `shouldBe` "abc.txt"
      guessFilename "http://example.com/foo/bar/abc.txt" `shouldBe` "abc.txt"
      guessFilename "abc.txt" `shouldBe` "abc.txt"

  describe "fileRange, hGet n bytes" $ do
    it "should work" $ do
      contentLB <- liftIO $ fileRange "/home/sylecn/persist/cache/ideaIC-2018.1.tar.gz" 0 2097151
      let first10Byte = LB.take 10 contentLB
      sha1sumOnBytes first10Byte `shouldBe` "04bdadb7bd09681ea2d3f84210feff6549b6ab45"
      LB.length contentLB `shouldBe` 2097152
      let last10Byte = LB.drop (2097152 - 10) contentLB
      sha1sumOnBytes last10Byte `shouldBe` "c643bc36514fce49013d31f80775dbbc9bf9e9a7"

  describe "sha1sumFileRange" $ do
    it "should work" $ do
      sha1 <- liftIO $ sha1sumFileRange "/home/sylecn/persist/cache/ideaIC-2018.1.tar.gz" 0 2097151
      sha1 `shouldBe` "4690b050834d4059d40ad6f63bf91d6a4558bb71"

-- | like get, but accept path in [T.Text] format and do url safe encoding.
getPath :: [T.Text] -> WaiSession st SResponse
getPath = get . LB.toStrict . toLazyByteString . encodePathSegments

waiApp :: IO Application
waiApp = do
   rc <- defaultRDRuntimeConfig defaultRDConfig
   mkWaiApp rc

apiSpec :: Spec
apiSpec = with waiApp $ do
  describe "rd api" $ do
    it "has health check" $ do
      resp <- get "/rd/"
      liftIO (simpleStatus resp `shouldBe` status200)
      liftIO (jsonKeyAsBool resp "ok" `shouldBe` Just True)
      -- liftIO (shouldSatisfy 1 (\x -> True))
      liftIO (fmap (T.isInfixOf "reliable-download")
                   (jsonKeyAsText resp "app")
              `shouldBe` Just True)

    it "only respond with /rd/ prefix" $ do
      get "/" `shouldRespondWith` 404
      get "/abc" `shouldRespondWith` 404

    it "should parse basic path correctly" $ do
      _resp <- get "/test/rd/abc"
      liftIO (simpleStatus _resp `shouldBe` status200)
      liftIO (jsonKeyAsBool _resp "ok" `shouldBe` Just True)
      liftIO (jsonKeyAsText _resp "path" `shouldBe` Just "abc")
      _resp <- get "/test/rd/abc/def"
      liftIO (simpleStatus _resp `shouldBe` status200)
      liftIO (jsonKeyAsBool _resp "ok" `shouldBe` Just True)
      liftIO (jsonKeyAsText _resp "path" `shouldBe` Just "abc/def")
      _resp <- get "/test/rd/abc/def/"
      liftIO (simpleStatus _resp `shouldBe` status200)
      liftIO (jsonKeyAsBool _resp "ok" `shouldBe` Just True)
      liftIO (jsonKeyAsText _resp "path" `shouldBe` Just "abc/def/")

    it "should parse complex path correctly" $ do
      _resp <- getPath ["test", "rd", "abc def # ? ghi"]
      liftIO (simpleStatus _resp `shouldBe` status200)
      liftIO (jsonKeyAsBool _resp "ok" `shouldBe` Just True)
      liftIO (jsonKeyAsText _resp "path" `shouldBe` Just "abc def # ? ghi")

      _resp <- getPath ["test", "rd", "abc/def.jpg"]
      liftIO (simpleStatus _resp `shouldBe` status200)
      liftIO (jsonKeyAsBool _resp "ok" `shouldBe` Just True)
      liftIO (jsonKeyAsText _resp "path" `shouldBe` Just "abc/def.jpg")

      -- TODO the escape sequences is not supported by warp.
      -- _resp <- getPath ["test", "rd", "中文文件名.rar"]
      -- liftIO (simpleStatus _resp `shouldBe` status200)
      -- liftIO (jsonKeyAsBool _resp "ok" `shouldBe` Just True)
      -- liftIO (jsonKeyAsText _resp "path" `shouldBe` Just "中文文件名.rar")
