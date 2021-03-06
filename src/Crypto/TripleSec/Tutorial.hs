{-# OPTIONS_GHC -fno-warn-unused-imports #-}
module Crypto.TripleSec.Tutorial
    ( -- * Quickstart
      -- $quickstart

      -- * Decryption Is Easier
      -- $decryption

      -- * Efficient Cipher Use
      -- $efficiency

      -- * mtl
      -- $mtl
    ) where

import Control.Exception

import Crypto.TripleSec
-- $setup
-- >>> import Data.ByteString (ByteString)

-- $quickstart
--    There are 3 different ways to use this library which differ /only/ in how they deal with failure and where
--    they obtain a source of randomness (for generating the salt and IVs).
--
--    This quickstart will go through the same basics of encrypting, decrypting, and error handling for each of the 3
--    provided ways to use the library.
--
--    Let's say we have a password and a message to encrypt:
--
-- >>> let password = "my secret password" :: ByteString
-- >>> let message = "message that will be encrypted" :: ByteString
--
--    - Failure: Runtime exceptions (Control.Exception)
--
--    - Randomness: IO
--
-- >>> encryptIO password message :: IO ByteString
-- ...
--
-- >>> :{
--  encryptIO password "" `catch` \(e :: TripleSecException) -> do
--    print e
--    return ""
-- :}
-- EncryptionException ZeroLengthPlaintext
-- ""
--
-- >>> encryptIO password message >>= decryptIO password
-- "message that will be encrypted"
--
--    - Failure: @ Either TripleSecException a @
--
--    - Randomness: IO
--
-- >>> runTripleSecIO (encrypt password message :: TripleSecIOM ByteString) :: IO (Either TripleSecException ByteString)
-- ...
--
-- >>> :{
--  do
--    result <- runTripleSecIO (encrypt password "")
--    case result of Left err               -> print err
--                   Right encryptedMessage -> print encryptedMessage
-- :}
-- EncryptionException ZeroLengthPlaintext
--
-- >>> runTripleSecIO (encrypt password message >>= decrypt password)
-- Right "message that will be encrypted"
--
--    - Failure: @ Either TripleSecException a @
--
--    - Randomness: @ SystemDRG @ (obtained from 'IO' somewhere along the way)
--
-- >>> generator <- getSystemDRG :: IO SystemDRG
-- >>> evalTripleSecM (encrypt password message :: TripleSecM ByteString) generator :: Either TripleSecException ByteString
-- ...
--
-- >>> :{
--  do
--    generator <- getSystemDRG
--    let (result, newGenerator) = runTripleSecM (encrypt password "") generator
--    case result of Left err               -> print err
--                   Right encryptedMessage -> print encryptedMessage
-- :}
-- EncryptionException ZeroLengthPlaintext
--
-- >>> generator <- getSystemDRG
-- >>> evalTripleSecM (encrypt password message >>= decrypt password) generator
-- Right "message that will be encrypted"

-- $decryption
--    The TripleSec protocol requires random inputs for creating a new cipher (random salt) and actually encrypting data
--    (IVs). There is notably no need for randomness during decryption. To make your life a little easier, a "decryption
--    only" monad (and transformer) is included so you can drop the requirement of randomness from areas of your code
--    that are only concerned with decrypting things.
--
--    Here's how to use it.
--
-- >>> encrypted <- encryptIO "my password" "purity rocks!" :: IO ByteString -- Nothing new here
-- >>> let decrypted = runTripleSecDecryptM (decrypt "my password" encrypted) :: Either TripleSecException ByteString
-- >>> print decrypted
-- Right "purity rocks!"

-- $efficiency
--    The functions shown above are exactly what you need for one-off encryption and/or decryption. If this is your use
--    case, you can stop reading now.
--
--    However, if you need to encrypt or decrypt /many/ things at one time, the functions shown above may not be the
--    best way to go. The problem is, each call to 'encrypt' or 'decrypt' rebuilds the cipher (a purposely /very/
--    expensive operation).
--
--    All three monads shown above ('IO', 'TripleSecIOM', 'TripleSecM') provide a way create a cipher once for multiple
--    uses. The examples below will only show how this is done with 'TripleSecIOM' for brevity.
--
--    Note: When creating a cipher for multiple encryptions, please make sure you understand the trade-off that comes
--    from re-using a cipher salt. The potential downsides of this for TripleSec are /exactly/ the same with any other
--    encryption.
--
-- >>> :{
--  runTripleSecIO $ do
--    cipher <- newCipher "mypassword" :: TripleSecIOM (TripleSec ByteString)
--    mapM (encryptWithCipher cipher) ["message1", "message2", "message3"] :: TripleSecIOM [ByteString]
-- :}
-- ...
--
--    Failures are short circuiting.
--
-- >>> :{
--  runTripleSecIO $ do
--    cipher <- newCipher "mypassword" :: TripleSecIOM (TripleSec ByteString)
--    mapM (encryptWithCipher cipher) ["message1", "", "message3"]
-- :}
-- Left (EncryptionException ZeroLengthPlaintext)
--
--    Decryption works the same way.
--
-- >>> :{
--  runTripleSecIO $ do
--    cipher <- newCipher "mypassword" :: TripleSecIOM (TripleSec ByteString)
--    encryptedList <- mapM (encryptWithCipher cipher) ["message1", "message2", "message3"]
--    mapM (decryptWithCipher cipher) encryptedList
-- :}
-- Right ["message1","message2","message3"]
--
--    Keep in mind, @ newCipher @ uses a random salt. @ decryptWithCipher @ will fail if given a cipher with a
--    salt that doesn't match the salt stored in the ciphertext.
--
-- >>> :{
--  runTripleSecIO $ do
--    cipher <- newCipher "mypassword" :: TripleSecIOM (TripleSec ByteString)
--    encryptedList <- mapM (encryptWithCipher cipher) ["message1", "message2", "message3"]
--    secondCipher <- newCipher "mypassword"  -- Note: Same password!
--    mapM (decryptWithCipher secondCipher) encryptedList
-- :}
-- Left (DecryptionException MisMatchedCipherSalt)
--
--    Assuming you /know/ a batch of encrypted messages were all encrypted with the same cipher, you can reconstruct
--    that cipher from one of the messages.
--
-- >>> :{
--  runTripleSecIO $ do
--    cipher <- newCipher "mypassword" :: TripleSecIOM (TripleSec ByteString)
--    encryptedList@(e1:_) <- mapM (encryptWithCipher cipher) ["message1", "message2", "message3"]
--    (_, firstCipherSalt, _) <- checkPrefix e1
--    secondCipher <- newCipherWithSalt "mypassword" firstCipherSalt
--    mapM (decryptWithCipher secondCipher) encryptedList
-- :}
-- Right ["message1","message2","message3"]

-- $mtl
--
--    The tutorial has shown you how to work with both 'TripleSecIOM' and 'TripleSecM'. In reality these are just type
--    aliases for @ TripleSecIOT IO @ and @ TripleSecT Identity @ respectively.
--
--    This library exports these monad transformers themselves for your convenience. It also exports @ runTripleSecT @
--    and @ evalTripleSecT @ for use with 'TripleSecT'.
--
--    However, at this time, only 'MonadTrans' instances of these transformers have been implemented in this library.