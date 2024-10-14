class JSON
{
   var text;
   var ch = "";
   var at = 0;
   function JSON()
   {
   }
   function stringify(arg)
   {
      var _loc4_ = undefined;
      var _loc3_ = undefined;
      var _loc7_ = undefined;
      var _loc2_ = "";
      var _loc5_ = undefined;
      switch(typeof arg)
      {
         case "object":
            if(arg)
            {
               if(arg instanceof Array)
               {
                  _loc3_ = 0;
                  while(_loc3_ < arg.length)
                  {
                     _loc5_ = this.stringify(arg[_loc3_]);
                     if(_loc2_)
                     {
                        _loc2_ += ",";
                     }
                     _loc2_ += _loc5_;
                     _loc3_ = _loc3_ + 1;
                  }
                  return "[" + _loc2_ + "]";
               }
               if(typeof arg.toString != "undefined")
               {
                  for(_loc3_ in arg)
                  {
                     _loc5_ = arg[_loc3_];
                     if(typeof _loc5_ != "undefined" && typeof _loc5_ != "function")
                     {
                        _loc5_ = this.stringify(_loc5_);
                        if(_loc2_)
                        {
                           _loc2_ += ",";
                        }
                        _loc2_ += this.stringify(_loc3_) + ":" + _loc5_;
                     }
                  }
                  return "{" + _loc2_ + "}";
               }
            }
            return "null";
         case "number":
            return !isFinite(arg) ? "null" : String(arg);
         case "string":
            _loc7_ = arg.length;
            _loc2_ = "\"";
            _loc3_ = 0;
            while(_loc3_ < _loc7_)
            {
               _loc4_ = arg.charAt(_loc3_);
               if(_loc4_ >= " ")
               {
                  if(_loc4_ == "\\" || _loc4_ == "\"")
                  {
                     _loc2_ += "\\";
                  }
                  _loc2_ += _loc4_;
               }
               else
               {
                  switch(_loc4_)
                  {
                     case "\b":
                        _loc2_ += "\\b";
                        break;
                     case "\f":
                        _loc2_ += "\\f";
                        break;
                     case "\n":
                        _loc2_ += "\\n";
                        break;
                     case "\r":
                        _loc2_ += "\\r";
                        break;
                     case "\t":
                        _loc2_ += "\\t";
                        break;
                     default:
                        _loc4_ = _loc4_.charCodeAt();
                        _loc2_ += "\\u00" + Math.floor(_loc4_ / 16).toString(16) + (_loc4_ % 16).toString(16);
                  }
               }
               _loc3_ += 1;
            }
            return _loc2_ + "\"";
         case "boolean":
            return String(arg);
         default:
            return "null";
      }
   }
   function white()
   {
      while(this.ch)
      {
         if(this.ch <= " ")
         {
            this.next();
         }
         else
         {
            if(this.ch != "/")
            {
               break;
            }
            switch(this.next())
            {
               case "/":
                  while(this.next() && this.ch != "\n" && this.ch != "\r")
                  {
                  }
                  break;
               case "*":
                  this.next();
                  while(true)
                  {
                     if(this.ch)
                     {
                        if(this.ch == "*")
                        {
                           if(this.next() == "/")
                           {
                              break;
                           }
                        }
                        else
                        {
                           this.next();
                        }
                     }
                     else
                     {
                        this.error("Unterminated comment");
                     }
                  }
                  this.next();
                  continue;
               default:
                  this.error("Syntax error");
            }
         }
      }
   }
   function error(m)
   {
      throw {name:"JSONError",message:m,at:this.at - 1,text:this.text};
   }
   function next()
   {
      this.ch = this.text.charAt(this.at);
      this.at += 1;
      return this.ch;
   }
   function str()
   {
      var _loc5_ = undefined;
      var _loc2_ = "";
      var _loc4_ = undefined;
      var _loc3_ = undefined;
      var _loc6_ = false;
      if(this.ch == "\"")
      {
         while(this.next())
         {
            if(this.ch == "\"")
            {
               this.next();
               return _loc2_;
            }
            if(this.ch == "\\")
            {
               switch(this.next())
               {
                  case "b":
                     _loc2_ += "\b";
                     break;
                  case "f":
                     _loc2_ += "\f";
                     break;
                  case "n":
                     _loc2_ += "\n";
                     break;
                  case "r":
                     _loc2_ += "\r";
                     break;
                  case "t":
                     _loc2_ += "\t";
                     break;
                  case "u":
                     _loc3_ = 0;
                     _loc5_ = 0;
                     while(_loc5_ < 4)
                     {
                        _loc4_ = parseInt(this.next(),16);
                        if(!isFinite(_loc4_))
                        {
                           _loc6_ = true;
                           break;
                        }
                        _loc3_ = _loc3_ * 16 + _loc4_;
                        _loc5_ += 1;
                     }
                     if(_loc6_)
                     {
                        _loc6_ = false;
                        break;
                     }
                     _loc2_ += String.fromCharCode(_loc3_);
                     break;
                  default:
                     _loc2_ += this.ch;
               }
            }
            else
            {
               _loc2_ += this.ch;
            }
         }
      }
      this.error("Bad string");
   }
   function arr()
   {
      var _loc2_ = [];
      if(this.ch == "[")
      {
         this.next();
         this.white();
         if(this.ch == "]")
         {
            this.next();
            return _loc2_;
         }
         while(this.ch)
         {
            _loc2_.push(this.value());
            this.white();
            if(this.ch == "]")
            {
               this.next();
               return _loc2_;
            }
            if(this.ch != ",")
            {
               break;
            }
            this.next();
            this.white();
         }
      }
      this.error("Bad array");
   }
   function obj()
   {
      var _loc3_ = undefined;
      var _loc2_ = {};
      if(this.ch == "{")
      {
         this.next();
         this.white();
         if(this.ch == "}")
         {
            this.next();
            return _loc2_;
         }
         while(this.ch)
         {
            _loc3_ = this.str();
            this.white();
            if(this.ch != ":")
            {
               break;
            }
            this.next();
            _loc2_[_loc3_] = this.value();
            this.white();
            if(this.ch == "}")
            {
               this.next();
               return _loc2_;
            }
            if(this.ch != ",")
            {
               break;
            }
            this.next();
            this.white();
         }
      }
      this.error("Bad object");
   }
   function num()
   {
      var _loc2_ = "";
      var _loc3_ = undefined;
      if(this.ch == "-")
      {
         _loc2_ = "-";
         this.next();
      }
      while(this.ch >= "0" && this.ch <= "9")
      {
         _loc2_ += this.ch;
         this.next();
      }
      if(this.ch == ".")
      {
         _loc2_ += ".";
         this.next();
         while(this.ch >= "0" && this.ch <= "9")
         {
            _loc2_ += this.ch;
            this.next();
         }
      }
      if(this.ch == "e" || this.ch == "E")
      {
         _loc2_ += this.ch;
         this.next();
         if(this.ch == "-" || this.ch == "+")
         {
            _loc2_ += this.ch;
            this.next();
         }
         while(this.ch >= "0" && this.ch <= "9")
         {
            _loc2_ += this.ch;
            this.next();
         }
      }
      _loc3_ = Number(_loc2_);
      if(!isFinite(_loc3_))
      {
         this.error("Bad number");
      }
      return _loc3_;
   }
   function word()
   {
      switch(this.ch)
      {
         case "t":
            if(this.next() == "r" && this.next() == "u" && this.next() == "e")
            {
               this.next();
               return true;
            }
            break;
         case "f":
            if(this.next() == "a" && this.next() == "l" && this.next() == "s" && this.next() == "e")
            {
               this.next();
               return false;
            }
            break;
         case "n":
            if(this.next() == "u" && this.next() == "l" && this.next() == "l")
            {
               this.next();
               return null;
            }
            break;
      }
      this.error("Syntax error");
   }
   function value()
   {
      this.white();
      switch(this.ch)
      {
         case "{":
            return this.obj();
         case "[":
            return this.arr();
         case "\"":
            return this.str();
         case "-":
            return this.num();
         default:
            return !(this.ch >= "0" && this.ch <= "9") ? this.word() : this.num();
      }
   }
   function parse(_text)
   {
      this.text = _text;
      this.at = 0;
      this.ch = " ";
      return this.value();
   }
}