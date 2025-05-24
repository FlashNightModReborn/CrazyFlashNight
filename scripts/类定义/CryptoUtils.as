class CryptoUtils {
    private var rabbit:Rabbit;
    private var text1:String;
    private var text2:String;
    private var text3:String;

    public function CryptoUtils(text1:String, text2:String, text3:String) {
        this.rabbit = new Rabbit();
        this.text1 = text1;
        this.text2 = text2;
        this.text3 = text3;
    }

    public function generateKeyFile(hwCode:String, steamID:String, currentTime:String, wildcard:String, rabbitKey:String):String {
        // Convert to uppercase
        hwCode = hwCode.toUpperCase();
        steamID = steamID.toUpperCase();
        currentTime = currentTime.toUpperCase();

        // Step 1: Combine external inputs with initial texts
        var combinedText1:String = hwCode + this.text1;
        var combinedText2:String = steamID + this.text2;
        var combinedText3:String = currentTime + this.text3;

        // Step 2: Encrypt each combined text
        var encryptedText1:String = this.rc4Encrypt(hwCode, combinedText1);
        var encryptedText2:String = this.rabbitEncrypt(steamID, combinedText2);
        var encryptedText3:String = this.rc4Encrypt(currentTime, combinedText3);

        // Step 3: Base64 encode encrypted texts before concatenation
        encryptedText1 = Base64.encode(encryptedText1);
        encryptedText2 = Base64.encode(encryptedText2);
        encryptedText3 = Base64.encode(encryptedText3);

        // Concatenate the Base64 encoded encrypted texts using the wildcard
        var longText:String = encryptedText1 + wildcard + encryptedText2 + wildcard + encryptedText3;

        // Step 4: Encrypt the concatenated text with Rabbit
        this.rabbit.initialize(rabbitKey, "");
        var finalEncryptedText:String = this.rabbit.encrypt(longText);

        // Step 5: Encode the final encrypted text with Base64
        var base64Encoded:String = Base64.encode(finalEncryptedText);

        return base64Encoded;
    }


    public function verifyKeyFile(hwCode:String, steamID:String, currentTime:String, base64Encoded:String, wildcard:String, rabbitKey:String):Boolean {
        // Convert to uppercase
        hwCode = hwCode.toUpperCase();
        steamID = steamID.toUpperCase();
        currentTime = currentTime.toUpperCase();

        // Step 1: Decode the Base64 encoded string
        var encryptedData:String = Base64.decode(base64Encoded);

        // Step 2: Decrypt the encrypted data with Rabbit
        this.rabbit.initialize(rabbitKey, "");
        var decryptedLongText:String = this.rabbit.decrypt(encryptedData);

        // Step 3: Split the long text using the wildcard
        var texts:Array = decryptedLongText.split(wildcard);
        if (texts.length != 3) {
            return false;
        }

        // Base64 decode split texts before decrypting
        var decodedText1:String = Base64.decode(texts[0]);
        var decodedText2:String = Base64.decode(texts[1]);
        var decodedText3:String = Base64.decode(texts[2]);

        // Step 4: Decrypt each part and remove the external inputs
        var decryptedText1:String = this.rc4Decrypt(hwCode, decodedText1);
        var decryptedText2:String = this.rabbitDecrypt(steamID, decodedText2);
        var decryptedText3:String = this.rc4Decrypt(currentTime, decodedText3);

        decryptedText1 = decryptedText1.substring(hwCode.length);
        decryptedText2 = decryptedText2.substring(steamID.length);
        decryptedText3 = decryptedText3.substring(currentTime.length);

        // Step 5: Verify the decrypted texts with the original texts
        if (decryptedText1 == this.text1 && decryptedText2 == this.text2 && decryptedText3 == this.text3) {
            return true;
        } else {
            return false;
        }
    }


    private function rc4Encrypt(key:String, data:String):String {
        var rc4:RC4 = new RC4(key);
        var encryptedData:String = rc4.encrypt(data);
        return Base64.encode(encryptedData);
    }

    private function rc4Decrypt(key:String, data:String):String {
        var decodedData:String = Base64.decode(data);
        var rc4:RC4 = new RC4(key);
        return rc4.decrypt(decodedData);
    }

    private function rabbitEncrypt(key:String, data:String):String {
        this.rabbit.initialize(key, "");
        var encryptedData:String = this.rabbit.encrypt(data);
        return Base64.encode(encryptedData);
    }

    private function rabbitDecrypt(key:String, data:String):String {
        var decodedData:String = Base64.decode(data);
        this.rabbit.initialize(key, "");
        return this.rabbit.decrypt(decodedData);
    }

}