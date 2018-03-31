module IdePurescript.VSCode.Imports where

import Prelude

import Control.Monad.Aff (Aff)
import Control.Monad.Eff (Eff)
import Control.Monad.Eff.Class (liftEff)
import Control.Monad.Except (runExcept)
import Data.Either (Either(..))
import Data.Foreign (readArray, readString, toForeign)
import Data.Maybe (Maybe(..), maybe)
import Data.Nullable (toNullable)
import Data.Traversable (traverse)
import IdePurescript.VSCode.Assist (getActivePosInfo)
import IdePurescript.VSCode.Editor (identifierAtCursor)
import IdePurescript.VSCode.Types (MainEff, launchAffAndRaise)
import LanguageServer.IdePurescript.Commands (addCompletionImport, addModuleImportCmd, cmdName, getAvailableModulesCmd)
import LanguageServer.Types (Command(..), DocumentUri)
import LanguageServer.Uri (filenameToUri)
import VSCode.Input (showQuickPick, defaultInputOptions, getInput)
import VSCode.LanguageClient (LanguageClient, sendCommand)
import VSCode.TextDocument (getPath)
import VSCode.TextEditor (getDocument)
import VSCode.Window (getActiveTextEditor)

addIdentImport :: forall eff. LanguageClient -> Eff (MainEff eff) Unit
addIdentImport client = launchAffAndRaise $ void $ do
  liftEff getActivePosInfo >>= maybe (pure unit) \{ pos, uri, ed } -> do
    atCursor <- liftEff $ identifierAtCursor ed
    let defaultIdent = maybe "" _.word atCursor
    ident <- getInput (defaultInputOptions { prompt = toNullable $ Just "Identifier", value = toNullable $ Just defaultIdent })
    addIdentImportMod ident uri Nothing
  where
    addIdentImportMod :: String -> DocumentUri -> Maybe String -> Aff (MainEff eff) Unit
    addIdentImportMod ident uri mod = do
      let Command { command, arguments } = addCompletionImport ident mod Nothing uri
      res <- sendCommand client command arguments
      case runExcept $ readArray res of
        Right forArr
          | Right arr <- runExcept $ traverse readString forArr
          -> showQuickPick arr >>= maybe (pure unit) (addIdentImportMod ident uri <<< Just)
        _ -> pure unit

addModuleImport :: forall eff. LanguageClient -> Eff (MainEff eff) Unit
addModuleImport client = launchAffAndRaise $ void $ do
  modulesForeign <- sendCommand client (cmdName getAvailableModulesCmd) (toNullable Nothing)
  ed <- liftEff $ getActiveTextEditor
  case runExcept $ readArray modulesForeign, ed of
    Right arr1, Just ed
      | Right modules <- runExcept $ traverse readString arr1
      -> do
        pick <- showQuickPick modules
        uri <- liftEff $ filenameToUri =<< (getPath $ getDocument ed)
        case pick of
          Just modName -> void $ sendCommand client (cmdName addModuleImportCmd)
            (toNullable $ Just [ toForeign modName, toForeign $ toNullable Nothing, toForeign uri ])
          _ -> pure unit
    _, _ -> pure unit
