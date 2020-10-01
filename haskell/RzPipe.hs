module RzPipe (RzContext(), open, cmd, cmdj) where
import Data.Char
import Data.Word
import Network.HTTP
import System.IO
import System.Process
import System.Environment (getEnv)
import GHC.IO.Handle.FD
import System.Posix.Internals (FD)
import qualified Data.Aeson as JSON
import qualified Data.ByteString.Lazy as L

withPipes p = p { std_in = CreatePipe, std_out = CreatePipe, std_err = CreatePipe }

createProcess' args = fmap f $ createProcess (withPipes args) where
    f (Just i, Just o, Just e, h) = (i, o, e, h)
    f _ = error "createProcess': Failed to open pipes to the subprocess."

stringToLBS = L.pack . map (fromIntegral . ord)

lHTakeWhile :: (Word8 -> Bool) -> Handle -> IO L.ByteString
lHTakeWhile p h = do
    c <- fmap L.head $ L.hGet h 1
    if p c
        then fmap (c `L.cons`) $ lHTakeWhile p h
        else return L.empty

data RzContext = HttpCtx String
               | PipeCtx Handle Handle

open :: Maybe String -> IO RzContext
open (Just url@('h':'t':'t':'p':_)) = return $ HttpCtx (url ++ "/cmd/")
open (Just filename) = do
    (hIn, hOut, _, _) <- createProcess' $ proc "rizin" ["-q0", filename]
    lHTakeWhile (/= 0) hOut -- drop the inital null that rizin emits
    return $ PipeCtx hIn hOut
open Nothing = do
    hIn <- fdToHandle =<< (read::(String -> FD)) <$> getEnv "RZ_PIPE_OUT"
    hOut <- fdToHandle =<< (read::(String -> FD)) <$> getEnv "RZ_PIPE_IN"
    return $ PipeCtx hIn hOut

cmd :: RzContext -> String -> IO L.ByteString
cmd (HttpCtx url) cmd = fmap stringToLBS $ getResponseBody =<< simpleHTTP (getRequest (url ++ urlEncode cmd))
cmd (PipeCtx hIn hOut) cmd = hPutStrLn hIn cmd >> hFlush hIn >> lHTakeWhile (/= 0) hOut

cmdj :: JSON.FromJSON a => RzContext -> String -> IO (Maybe a)
cmdj = (fmap JSON.decode .) . cmd
