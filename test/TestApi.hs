-- module TestApi (main) where

-- GET /rd/some_complicated_url_safe_text

import Test.Hspec
import Test.Hspec.Wai
import Network.Wai.Test
import Network.HTTP.Types (status200, encodePathSegments, decodePathSegments)
import Data.Binary.Builder (toLazyByteString)
import Network.Wai (Application)

import qualified Data.Aeson as J
import qualified Data.ByteString.Lazy as LB
import qualified Data.Text as T
import qualified Data.HashMap.Strict as H
import qualified Database.Redis as R

import App (mkWaiApp)

-- | decode response as json object.
jsonObject :: SResponse -> Maybe J.Object
jsonObject resp = J.decode $ simpleBody resp

-- | decode response as json object, then retrieve a key.
jsonKey :: SResponse -> T.Text -> Maybe J.Value
jsonKey resp key = do
  map <- jsonObject resp
  H.lookup key map

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
      ((decodePathSegments . LB.toStrict . toLazyByteString . encodePathSegments) ["中文1", "路径2"]) `shouldBe` ["中文1", "路径2"]

-- | like get, but accept path in [T.Text] format and do url safe encoding.
getPath :: [T.Text] -> WaiSession SResponse
getPath = get . LB.toStrict . toLazyByteString . encodePathSegments

waiApp :: IO Application
waiApp = do
   conn <- R.connect R.defaultConnectInfo
   mkWaiApp conn

apiSpec :: Spec
apiSpec = with waiApp $ do
  describe "rd api" $ do
    it "has health check" $ do
      resp <- get "/rd/"
      liftIO (simpleStatus resp `shouldBe` status200)
      liftIO ((jsonKeyAsBool resp "ok") `shouldBe` Just True)
      -- liftIO (shouldSatisfy 1 (\x -> True))
      liftIO ((fmap (T.isInfixOf "reliable-download")
                    (jsonKeyAsText resp "app"))
              `shouldBe` Just True)

    it "only respond with /rd/ prefix" $ do
      get "/" `shouldRespondWith` 404
      get "/abc" `shouldRespondWith` 404

    it "should parse basic path correctly" $ do
      resp <- get "/rd/abc"
      liftIO (simpleStatus resp `shouldBe` status200)
      liftIO ((jsonKeyAsBool resp "ok") `shouldBe` Just True)
      liftIO ((jsonKeyAsText resp "path") `shouldBe` Just "abc")
      resp <- get "/rd/abc/def"
      liftIO (simpleStatus resp `shouldBe` status200)
      liftIO ((jsonKeyAsBool resp "ok") `shouldBe` Just True)
      liftIO ((jsonKeyAsText resp "path") `shouldBe` Just "abc/def")
      resp <- get "/rd/abc/def/"
      liftIO (simpleStatus resp `shouldBe` status200)
      liftIO ((jsonKeyAsBool resp "ok") `shouldBe` Just True)
      liftIO ((jsonKeyAsText resp "path") `shouldBe` Just "abc/def/")

    it "should parse complex path correctly" $ do
      resp <- getPath ["rd", "abc def # ? ghi"]
      liftIO (simpleStatus resp `shouldBe` status200)
      liftIO ((jsonKeyAsBool resp "ok") `shouldBe` Just True)
      liftIO ((jsonKeyAsText resp "path") `shouldBe` Just "abc def # ? ghi")

      resp <- getPath ["rd", "abc/def.jpg"]
      liftIO (simpleStatus resp `shouldBe` status200)
      liftIO ((jsonKeyAsBool resp "ok") `shouldBe` Just True)
      liftIO ((jsonKeyAsText resp "path") `shouldBe` Just "abc/def.jpg")

      -- resp <- getPath ["rd", "中文文件名.rar"]
      -- liftIO (simpleStatus resp `shouldBe` status200)
      -- liftIO ((jsonKeyAsBool resp "ok") `shouldBe` Just True)
      -- liftIO ((jsonKeyAsText resp "path") `shouldBe` Just "中文文件名.rar")

main :: IO ()
main = do
  hspec spec
  hspec apiSpec
