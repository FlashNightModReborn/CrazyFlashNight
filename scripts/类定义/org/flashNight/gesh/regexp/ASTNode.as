class org.flashNight.gesh.regexp.ASTNode {
    public var type:String;
    public var value:Object;
    public var child:ASTNode;
    public var children:Array;
    public var left:ASTNode;
    public var right:ASTNode;
    public var min:Number;
    public var max:Number;
    public var negated:Boolean;
    public var capturing:Boolean;
    public var greedy:Boolean;
    public var groupNumber:Number;

    public function ASTNode(type:String) {
        this.type = type;
        this.value = null;
        this.child = null;
        this.children = null;
        this.left = null;
        this.right = null;
        this.min = 1;
        this.max = 1;
        this.negated = false;
        this.capturing = false;
        this.greedy = true;
        this.groupNumber = 0;
    }

    public function getFixedLength():Number {
        switch(this.type) {
            case 'Literal':
                return 1;
            case 'CharacterClass':
                return 1;
            case 'PredefinedCharacterClass':
                return 1;
            case 'Sequence':
                var totalLength:Number = 0;
                for (var i:Number = 0; i < this.children.length; i++) {
                    totalLength += this.children[i].getFixedLength();
                }
                return totalLength;
            case 'Group':
                return this.child.getFixedLength();
            case 'Quantifier':
                if (this.min === this.max) {
                    return this.child.getFixedLength() * this.min;
                } else {
                    throw new Error("Cannot determine fixed length for Quantifier node with variable min and max.");
                }
            case 'Alternation':
                var leftLength:Number = this.left.getFixedLength();
                var rightLength:Number = this.right.getFixedLength();
                if (leftLength === rightLength) {
                    return leftLength;
                } else {
                    throw new Error("Cannot determine fixed length for Alternation node with differing alternation lengths.");
                }
            default:
                throw new Error("Cannot determine fixed length for ASTNode type: " + this.type);
        }
    }

    public function match(input:String, position:Number, captures:Array, ignoreCase:Boolean, multiline:Boolean, dotAll:Boolean):Object {
        if (multiline === undefined) multiline = false;
        if (dotAll === undefined) dotAll = false;
        var result:Object = { matched: false, position: position };
        var inputLen:Number = length(input);
        if (position > inputLen) {
            return result;
        }

        switch(this.type) {
            case 'Literal':
                if (position < inputLen && charEquals(input.charAt(position), String(this.value), ignoreCase)) {
                    result.matched = true;
                    result.position = position + 1;
                }
                break;

            case 'Any':
                if (position < inputLen) {
                    var anyChar:String = input.charAt(position);
                    if (anyChar == '\n' && !dotAll) {
                        result.matched = false;
                    } else {
                        result.matched = true;
                        result.position = position + 1;
                    }
                }
                break;

            case 'Sequence':
                var seqPos:Number = position;
                var seqCaptures:Array = captures.slice();
                var seqMatched:Boolean = true;
                
                for (var si:Number = 0; si < this.children.length; si++) {
                    var seqChild:ASTNode = this.children[si];
                    var seqChildResult:Object = seqChild.match(input, seqPos, seqCaptures, ignoreCase, multiline, dotAll);
                    if (!seqChildResult.matched) {
                        seqMatched = false;
                        break;
                    }
                    seqPos = seqChildResult.position;
                }
                
                if (seqMatched) {
                    for (var sk:Number = 0; sk < seqCaptures.length; sk++) {
                        captures[sk] = seqCaptures[sk];
                    }
                    result.matched = true;
                    result.position = seqPos;
                }
                break;

            case 'CharacterClass':
                if (position < inputLen) {
                    var ccChar:String = input.charAt(position);
                    var inSet:Boolean = false;
                    var ccVal = this.value;
                    
                    for (var cj:Number = 0; cj < ccVal.length; cj++) {
                        if (charEquals(ccVal[cj], ccChar, ignoreCase)) {
                            inSet = true;
                            break;
                        }
                    }
                    if (this.negated) {
                        inSet = !inSet;
                    }
                    
                    if (inSet) {
                        result.matched = true;
                        result.position = position + 1;
                    }
                }
                break;

            case 'PredefinedCharacterClass':
                if (position < inputLen) {
                    var pccChar:String = input.charAt(position);
                    var pccMatched:Boolean = false;
                    switch(this.value) {
                        case 'd': pccMatched = isDigit(pccChar); break;
                        case 'D': pccMatched = !isDigit(pccChar); break;
                        case 'w': pccMatched = isWordChar(pccChar); break;
                        case 'W': pccMatched = !isWordChar(pccChar); break;
                        case 's': pccMatched = isWhitespace(pccChar); break;
                        case 'S': pccMatched = !isWhitespace(pccChar); break;
                    }
                    if (pccMatched) {
                        result.matched = true;
                        result.position = position + 1;
                    }
                }
                break;

            case 'Quantifier':
                if (this.child == null) {
                    throw new Error("Quantifier node has no child.");
                }

                var qMaxPossible:Number = Math.min(this.max, inputLen - position);
                var qMinRequired:Number = this.min;

                if (this.greedy) {
                    for (var qCount:Number = qMaxPossible; qCount >= qMinRequired; qCount--) {
                        var qTempPos:Number = position;
                        var qTempCaptures:Array = captures.slice();
                        var qAllMatched:Boolean = true;

                        for (var qc:Number = 0; qc < qCount; qc++) {
                            var qTempMatch:Object = this.child.match(input, qTempPos, qTempCaptures, ignoreCase, multiline, dotAll);
                            if (qTempMatch.matched) {
                                qTempPos = qTempMatch.position;
                            } else {
                                qAllMatched = false;
                                break;
                            }
                        }

                        if (qAllMatched) {
                            result.matched = true;
                            result.position = qTempPos;
                            for (var qm:Number = 0; qm < qTempCaptures.length; qm++) {
                                captures[qm] = qTempCaptures[qm];
                            }
                            break;
                        }
                    }
                } else {
                    // 非贪婪：从最小到最大尝试
                    for (var ngCount:Number = qMinRequired; ngCount <= qMaxPossible; ngCount++) {
                        var ngTempPos:Number = position;
                        var ngTempCaptures:Array = captures.slice();
                        var ngAllMatched:Boolean = true;

                        for (var ngc:Number = 0; ngc < ngCount; ngc++) {
                            var ngTempMatch:Object = this.child.match(input, ngTempPos, ngTempCaptures, ignoreCase, multiline, dotAll);
                            if (ngTempMatch.matched) {
                                ngTempPos = ngTempMatch.position;
                            } else {
                                ngAllMatched = false;
                                break;
                            }
                        }

                        if (ngAllMatched) {
                            result.matched = true;
                            result.position = ngTempPos;
                            for (var ngm:Number = 0; ngm < ngTempCaptures.length; ngm++) {
                                captures[ngm] = ngTempCaptures[ngm];
                            }
                            break;
                        }
                    }
                }
                break;

            case 'Alternation':
                var altLeftCaptures:Array = captures.slice();
                var altLeftResult:Object = this.left.match(input, position, altLeftCaptures, ignoreCase, multiline, dotAll);
                if (altLeftResult.matched) {
                    for (var altL:Number = 0; altL < altLeftCaptures.length; altL++) {
                        captures[altL] = altLeftCaptures[altL];
                    }
                    result.matched = true;
                    result.position = altLeftResult.position;
                } else {
                    var altRightCaptures:Array = captures.slice();
                    var altRightResult:Object = this.right.match(input, position, altRightCaptures, ignoreCase, multiline, dotAll);
                    if (altRightResult.matched) {
                        for (var altR:Number = 0; altR < altRightCaptures.length; altR++) {
                            captures[altR] = altRightCaptures[altR];
                        }
                        result.matched = true;
                        result.position = altRightResult.position;
                    }
                }
                break;

            case 'Group':
                var gStartPos:Number = position;
                var gCaptures:Array = captures.slice();
                var gResult:Object = this.child.match(input, position, gCaptures, ignoreCase, multiline, dotAll);
                if (gResult.matched) {
                    result.matched = true;
                    result.position = gResult.position;
                    if (this.capturing) {
                        var gMatch:String = input.substring(gStartPos, gResult.position);
                        if (this.groupNumber > 0) {
                            gCaptures[this.groupNumber] = gMatch;
                        }
                    }
                    for (var gIdx:Number = 0; gIdx < gCaptures.length; gIdx++) {
                        captures[gIdx] = gCaptures[gIdx];
                    }
                }
                break;

            case 'BackReference':
                var brGroupNum:Number = Number(this.value);
                if (captures.length > brGroupNum && captures[brGroupNum] != undefined) {
                    var brContent:String = captures[brGroupNum];
                    var brEndPos:Number = position + brContent.length;
                    if (brEndPos <= inputLen) {
                        var brMatchStr:String = input.substring(position, brEndPos);
                        if (charEquals(brMatchStr, brContent, ignoreCase)) {
                            result.matched = true;
                            result.position = brEndPos;
                        }
                    }
                }
                break;

            case 'Anchor':
                if (this.value == 'start') {
                    if (position == 0 || (multiline && position > 0 && input.charAt(position - 1) == '\n')) {
                        result.matched = true;
                        result.position = position;
                    }
                } else if (this.value == 'end') {
                    if (position == inputLen || (multiline && position < inputLen && input.charAt(position) == '\n')) {
                        result.matched = true;
                        result.position = position;
                    }
                }
                break;

            case 'WordBoundary':
                var wbLeft:Boolean = position > 0 && isWordChar(input.charAt(position - 1));
                var wbRight:Boolean = position < inputLen && isWordChar(input.charAt(position));
                var atWB:Boolean = wbLeft != wbRight;
                
                if (this.value == 'b') {
                    if (atWB) {
                        result.matched = true;
                        result.position = position;
                    }
                } else if (this.value == 'B') {
                    if (!atWB) {
                        result.matched = true;
                        result.position = position;
                    }
                }
                break;

            case 'PositiveLookahead':
                var laCaptures:Array = captures.slice();
                var laResult:Object = this.child.match(input, position, laCaptures, ignoreCase, multiline, dotAll);
                if (laResult.matched) {
                    result.matched = true;
                    result.position = position;
                }
                break;

            case 'NegativeLookahead':
                var nlaCaptures:Array = captures.slice();
                var nlaResult:Object = this.child.match(input, position, nlaCaptures, ignoreCase, multiline, dotAll);
                if (!nlaResult.matched) {
                    result.matched = true;
                    result.position = position;
                }
                break;

            case 'PositiveLookbehind':
                try {
                    var lbLen:Number = this.child.getFixedLength();
                } catch (e:Error) {
                    throw new Error("PositiveLookbehind requires a fixed-length pattern. " + e.message);
                }
                var lbStart:Number = position - lbLen;
                if (lbStart >= 0) {
                    var lbCaptures:Array = captures.slice();
                    var lbResult:Object = this.child.match(input, lbStart, lbCaptures, ignoreCase, multiline, dotAll);
                    if (lbResult.matched && lbResult.position == position) {
                        result.matched = true;
                        result.position = position;
                    }
                }
                break;

            case 'NegativeLookbehind':
                try {
                    var nlbLen:Number = this.child.getFixedLength();
                } catch (e:Error) {
                    throw new Error("NegativeLookbehind requires a fixed-length pattern. " + e.message);
                }
                var nlbStart:Number = position - nlbLen;
                if (nlbStart >= 0) {
                    var nlbCaptures:Array = captures.slice();
                    var nlbResult:Object = this.child.match(input, nlbStart, nlbCaptures, ignoreCase, multiline, dotAll);
                    if (!nlbResult.matched || nlbResult.position != position) {
                        result.matched = true;
                        result.position = position;
                    }
                } else {
                    result.matched = true;
                    result.position = position;
                }
                break;
        }

        return result;
    }

    private function charEquals(a:String, b:String, ignoreCase:Boolean):Boolean {
        if (ignoreCase) {
            return a.toLowerCase() == b.toLowerCase();
        } else {
            return a == b;
        }
    }

    private function isDigit(char:String):Boolean {
        var code:Number = char.charCodeAt(0);
        return code >= 48 && code <= 57;
    }

    private function isWordChar(char:String):Boolean {
        var code:Number = char.charCodeAt(0);
        return (code >= 48 && code <= 57) ||
               (code >= 65 && code <= 90) ||
               (code >= 97 && code <= 122) ||
               (char == '_');
    }

    private function isWhitespace(char:String):Boolean {
        return char == ' ' || char == '\t' || char == '\n' || char == '\r' || char == '\f' || char == '\v';
    }
}
