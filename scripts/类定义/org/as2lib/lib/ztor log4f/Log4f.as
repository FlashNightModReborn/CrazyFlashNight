/*
 * Log4f
 */

/**
 * <code>Log4f</code>
 *
 * @version 1.0  2005.01.12
 * @author  Andrey Orlov
 *
 */
class Log4f {

  public  static var DEBUG : Number  = 0;
  public  static var INFO  : Number  = 1;
  public  static var WARN  : Number  = 2;
  public  static var ERROR : Number  = 3;
  public  static var FATAL : Number  = 4;

  public  static var LOG4F : Number  = 5;

  // _so  structure:
  // timestamp : Number - log message timestamp
  // progstamp : String - program id + timestamp  ( call init time )
  // msgtype   : Number - message type DEBUG..FATAL
  // msgnum    : Number - message type DEBUG..FATAL
  // header    : String - message title
  // body      : String - message body
  private static var __so       : SharedObject = null;

  // _so_dir  structure:
  // lts : Number - Last Logging TimeStamp 
  // fn  : Number - Current Logger File Number (from 0 to 9999)
  private static var __so_dir   : SharedObject = null;  

  private static var __name      : String  = "";  
  private static var __prog      : String  = "";  
  private static var __logger    : String  = "logfile";  
  private static var __maxmsg    : Number  = 200;  
  private static var __minmsg    : Number  = 180;  
  private static var __minlevel  : Number  = INFO;  
  private static var __flush     : Boolean = true;  
  private static var __reset     : Boolean = false;  

  private static var __timestamp    : Number  = 0;  
  private static var __oldtimestamp : Number  = 0;  
  private static var __number       : Number  = 0;  

  private static var __initparm : Boolean = false;  
  private static var __init     : Boolean = false;  


  /**
   * init
   * 
   * @param p_init - XML or XMLNode contains parameters for logger
   * program    = "program_name"
   * name       = "logger_name"
   * capacity   = "100"    (max records in one logger file)
   * keepmsg    = "99"     (how many records keep in releasing process)
   * level      = "1"      (lowest level. Only message with type >= level are processed)
   * flush      = "true"   (if false - flush logger data manualy)
   * reset      = "true"   (if true - loggers files resets before using)
   */ 
  public static function init (p_init : XMLNode) : Void {
    if (__initparm) { return; }
    if (p_init.hasChildNodes()) { p_init = p_init.firstChild; }

    var x_p  = p_init.attributes["program"];
    var x_l  = p_init.attributes["name"];
    var x_m  = p_init.attributes["capacity"];
    var x_k  = p_init.attributes["keep"];
    var x_t  = p_init.attributes["level"];
    var x_f  = p_init.attributes["flush"];
    var x_r  = p_init.attributes["reset"];

    if (x_p!=undefined) { __prog = x_p+" "+new Date().getTime(); __name=x_p;}
    if (x_l!=undefined) { __logger = x_l; }
    if (x_m!=undefined) { 
      __maxmsg = parseInt(x_m);
      if ((__maxmsg<1) || (__maxmsg>10000) || isNaN(__maxmsg)) { __maxmsg = 100; }
    }
    
    if (x_k!=undefined) { 
      __minmsg = parseInt(x_k);
      if ((__minmsg<0) || (__minmsg>=__maxmsg) || isNaN(__minmsg)) { __minmsg = __maxmsg-1; }
    } else { __minmsg = __maxmsg-1; }
  
    if (x_t!=undefined) { 
      switch (x_t.toUpperCase()) {
        case "INFO"    : __minlevel = 1; break;
        case "WARN"    : __minlevel = 2; break;
        case "ERROR"   : __minlevel = 3; break;
        case "FATAL"   : __minlevel = 4; break;
        case "DEBUG"   : 
        default        : __minlevel = 0; break;
      }
    }
    
    if (x_f!=undefined) { 
      if (x_f.toUpperCase()=="FALSE") { __flush = false; }
    }

    if (x_r!=undefined) { 
      if (x_r.toUpperCase()=="TRUE") { __reset = true; }
    }

    __initparm = true

//trace("["+__prog+"]"+"["+__logger+"]"+"["+__maxmsg+"]"+"["+__minmsg+"]"+"["+__minlevel+"]"+"["+__flush+"]");

  }


  /**
   * pushMessage - push Message to the pool
   *
   * @param p_type  - level of the message
   * @param p_head  - head
   * @param p_body  - body
   */
  private static function pushMessage( p_type : Number, p_head : String, p_body : String ) {
    __timestamp = new Date().getTime();
    __number++;
    if (__timestamp<=__oldtimestamp) { __timestamp = __oldtimestamp+1; }
    __oldtimestamp = __timestamp;
    __so_dir.data.lts = __timestamp;
    var x_obj = { 
      timestamp : __timestamp, 
      progstamp : __prog, 
      msgtype   : p_type,
      msgnum    : __number,
      header    : p_head,
      body      : p_body 
    } 
    __so.data.pool.push(x_obj);    
  }


  /**
   * log - log the message
   *
   * @param p_type  - level of the message
   * @param p_head  - head
   * @param p_body  - body
   */
  public static function log( p_type : Number, p_head : String, p_body : String ) {

    if (p_type<__minlevel) { return; }

    /* init logger files */ 
    if (!__init) {
      if (__prog=="") { __name="Program"; __prog = __name+" "+new Date().getTime(); }
      __so_dir = SharedObject.getLocal(__logger+"_dir", "/");  
      if (__reset) {
        if (__so_dir.data.fn!=undefined) {
          var o_logger;  
          for (var knum=0; knum<=__so_dir.data.fn; knum++) {
            o_logger = SharedObject.getLocal(__logger+"_"+knum, "/");  
            o_logger.clear();
            delete o_logger;
          }
          __so_dir.data.fn  = undefined;  
          __so_dir.data.lts = undefined;  
        }
      }
      
      if (__so_dir.data.lts==undefined) {
        __so_dir.data.lts=0;
        __so_dir.data.fn=0;
        __so_dir.flush();  
        __so = SharedObject.getLocal(__logger+"_"+__so_dir.data.fn, "/");  
        __so.data.pool = new Array();
        __so.flush();  
      } else { 
        __so = SharedObject.getLocal(__logger+"_"+__so_dir.data.fn, "/");  
      }
      __init=true;
      var x_date = new Date();
      pushMessage(LOG4F,__name+" started at "+x_date,"");
    }

    /* check fill over message pool */
    if ( __so.data.pool.length>=__maxmsg) {     
      if (__minmsg>0) {
          __so.data.pool.splice(0,__so.data.pool.length-__minmsg);
      } else {
        if (!__flush) { __so.flush(); }    
        delete __so;
        __so_dir.data.fn++;
        __so = SharedObject.getLocal(__logger+"_"+__so_dir.data.fn, "/");  
        __so.data.pool = new Array();
      }
    }

    /* create message object */    
    pushMessage(p_type,p_head,p_body);

    /* perform flush to disk */    
    if (__flush) {
      __so.flush();    
      __so_dir.flush();    
    }

  }


  /**
   * close - close logger
   */
  public static function close() {
    __so.flush();    
    __so_dir.flush();    
    delete __so;
    delete __so_dir;
    __initparm = false;  
    __init     = false;  
  }

}