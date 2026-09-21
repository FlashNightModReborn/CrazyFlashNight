// The network helper owns no command execution authority. It forwards encrypted
// TLS bytes between loopback and a userspace Tailscale node; never advertises routes.
package main

import (
 "bufio"
 "context"
 "encoding/json"
 "flag"
 "fmt"
 "io"
 "net"
 "os"
 "strings"
 "sync"
 "time"
 "tailscale.com/tsnet"
)

var output sync.Mutex
func emit(v any) { output.Lock(); defer output.Unlock(); _ = json.NewEncoder(os.Stdout).Encode(v) }
func bridge(a, b net.Conn) { defer a.Close(); defer b.Close(); done := make(chan struct{}); go func(){ _,_ = io.Copy(a,b); close(done) }(); _,_ = io.Copy(b,a); a.Close(); b.Close(); <-done }
func main() {
 dir := flag.String("state", "", "private per-session state directory")
 host := flag.String("hostname", "cf7-support", "node name")
 local := flag.String("local", "", "loopback TLS target (listen mode)")
 target := flag.String("target", "", "tailnet TLS target (dial mode)")
 flag.Parse()
 if *dir == "" || ((*local == "") == (*target == "")) { fmt.Fprintln(os.Stderr,"invalid network arguments"); os.Exit(2) }
 // No inherited account secrets or alternate control planes. Enrollment is visible.
 for _, k := range []string{"TS_AUTHKEY","TS_AUTH_KEY","TS_CLIENT_SECRET","TS_CLIENT_ID","TS_CONTROL_URL","TSNET_FORCE_LOGIN"} { _ = os.Unsetenv(k) }
 ctx, cancel := context.WithCancel(context.Background()); defer cancel()
 // Parent lifetime is the authority boundary; stdin closes when parent crashes.
 go func(){ s:=bufio.NewScanner(os.Stdin); for s.Scan(){ if s.Text()=="stop" { break } }; cancel() }()
 srv := &tsnet.Server{Dir:*dir, Hostname:*host, Ephemeral:true, Logf:func(string,...any){}, UserLogf:func(f string,a ...any){
   // Authentication links are sent only to the parent's private pipe, never logged.
   for _, word := range strings.Fields(fmt.Sprintf(f,a...)) { if strings.HasPrefix(word,"https://login.tailscale.com/"){ emit(map[string]any{"event":"authorization","url":word}) } }
 }}
 defer srv.Close()
 if err:=srv.Start(); err!=nil { emit(map[string]any{"event":"error","message":err.Error()}); return }
 ready:=make(chan bool,1)
 go func(){ _,err:=srv.Up(ctx); if err!=nil { emit(map[string]any{"event":"error","message":"网络准备未完成"}); ready<-false } else {ready<-true} }()
 select { case <-ctx.Done(): return; case ok:=<-ready: if !ok { return } }
 var listener net.Listener
 var err error
 if *local!="" { listener,err=srv.Listen("tcp",":38475") } else { listener,err=net.Listen("tcp","127.0.0.1:0") }
 if err!=nil { emit(map[string]any{"event":"error","message":err.Error()}); return }
 defer listener.Close()
 v4,_:=srv.TailscaleIPs()
 emit(map[string]any{"event":"ready","host":v4.String(),"port":38475,"local":listener.Addr().String()})
 go func(){ <-ctx.Done(); listener.Close(); srv.Close() }()
 go func(){ ticker:=time.NewTicker(15*time.Second); defer ticker.Stop(); for { select {case <-ctx.Done():return;case <-ticker.C:
   lc,e:=srv.LocalClient(); if e!=nil {continue}; st,e:=lc.Status(ctx); if e!=nil {continue}; peers:=[]map[string]any{}
   for _,p:=range st.Peer {if p.Active {peers=append(peers,map[string]any{"direct":p.CurAddr!="","relayRegion":p.Relay,"rxBytes":p.RxBytes,"txBytes":p.TxBytes})}}
   emit(map[string]any{"event":"route","peers":peers})
 }}}()
 for { conn,e:=listener.Accept(); if e!=nil {return}; go func(){
   var remote net.Conn; var e error
   dialCtx,c:=context.WithTimeout(ctx,30*time.Second); defer c()
   if *local!="" { d:=net.Dialer{}; remote,e=d.DialContext(dialCtx,"tcp",*local) } else { remote,e=srv.Dial(dialCtx,"tcp",*target) }
   if e!=nil {conn.Close(); return}; bridge(conn,remote)
 }() }
}
