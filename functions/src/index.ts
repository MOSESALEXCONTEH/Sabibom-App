import {initializeApp} from "firebase-admin/app";
import {setGlobalOptions} from "firebase-functions/v2";

initializeApp();

setGlobalOptions({
  region: "us-central1",
  maxInstances: 20,
});

export {
  createPinataUploadUrl,
  uploadBusinessLogoViaProxy,
} from "./pinata/createPinataUploadUrl";
export {parseSabiReceiptCommand} from "./sabi/parseSabiReceiptCommand";
export {answerSabiBusinessQuestion} from "./sabi/answerSabiBusinessQuestion";
