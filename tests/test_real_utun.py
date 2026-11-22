#!/usr/bin/env python3
"""Privileged integration test: real macOS utun -> TCP/SLIP -> ICMP peer."""
import os, pathlib, re, socket, struct, subprocess, tempfile, threading, time
if os.geteuid()!=0: raise SystemExit('Run with sudo; this test creates a temporary utun interface.')
binary=os.environ.get('SSOCAT_TEST_BINARY','/opt/homebrew/bin/ssocat')
# Refuse to overlap an existing address or route in the test subnet.
local,remote='198.19.254.1','198.19.254.2'
for cmd in (['/sbin/ifconfig','-a'],['/usr/sbin/netstat','-rn']):
 if '198.19.254' in subprocess.check_output(cmd,text=True):
  raise SystemExit('Test subnet already present; no changes made.')
def checksum(data):
 if len(data)%2:data+=b'\0'
 n=sum(struct.unpack('!%dH'%(len(data)//2),data));n=(n>>16)+(n&65535);n+=(n>>16)
 return (~n)&65535
errors=[];seen=[];stop=threading.Event()
listener=socket.socket();listener.bind(('127.0.0.1',0));listener.listen();listener.settimeout(10)
def peer():
 try:
  conn,_=listener.accept()
  with conn:
   conn.settimeout(1);frame=bytearray();escaped=False
   while not stop.is_set():
    try:data=conn.recv(4096)
    except socket.timeout:continue
    if not data:break
    for byte in data:
     if byte==0xc0:
      pkt=bytes(frame);frame.clear();escaped=False
      if not pkt:continue
      if pkt[0]>>4!=4 or len(pkt)<28 or pkt[9]!=1:continue
      ihl=(pkt[0]&15)*4
      if pkt[ihl]!=8:continue
      assert socket.inet_ntoa(pkt[12:16])==local
      assert socket.inet_ntoa(pkt[16:20])==remote
      seen.append(pkt)
      reply=bytearray(pkt);reply[12:16]=pkt[16:20];reply[16:20]=pkt[12:16]
      reply[ihl]=0;reply[ihl+2:ihl+4]=b'\0\0'
      reply[ihl+2:ihl+4]=struct.pack('!H',checksum(bytes(reply[ihl:])))
      reply[10:12]=b'\0\0';reply[10:12]=struct.pack('!H',checksum(bytes(reply[:ihl])))
      wire=bytes(reply).replace(b'\xdb',b'\xdb\xdd').replace(b'\xc0',b'\xdb\xdc')+b'\xc0'
      # Deliberately split the reply across TCP writes.
      conn.sendall(wire[:7]);time.sleep(.01);conn.sendall(wire[7:])
     elif escaped:frame.append({0xdc:0xc0,0xdd:0xdb}[byte]);escaped=False
     elif byte==0xdb:escaped=True
     else:frame.append(byte)
 except Exception as exc:errors.append(exc)
thread=threading.Thread(target=peer,daemon=True);thread.start()
with tempfile.TemporaryFile(mode='w+') as log:
 proc=subprocess.Popen([binary,'-d','-d','TUN,iff-no-pi,iff-slip',f'TCP:127.0.0.1:{listener.getsockname()[1]}'],stdout=log,stderr=log)
 try:
  for _ in range(100):
   log.seek(0);text=log.read();match=re.search(r'created macOS interface (utun\d+)',text)
   if match:break
   if proc.poll() is not None:raise RuntimeError(text)
   time.sleep(.05)
  else:raise RuntimeError('Timed out waiting for utun')
  iface=match.group(1)
  subprocess.run(['/sbin/ifconfig',iface,'inet',local,remote,'netmask','255.255.255.255','up'],check=True)
  result=subprocess.run(['/sbin/ping','-n','-c','3','-W','2000','-p','c0db',remote],capture_output=True,text=True,timeout=15)
  print(result.stdout)
  assert result.returncode==0 and len(seen)>=3,(result.stderr,errors,len(seen))
  if errors:raise errors[0]
  print('PASS real utun, SLIP over TCP, fragmented ICMP replies, three ping round trips')
 finally:
  stop.set();proc.terminate();proc.wait(timeout=5);listener.close();thread.join(timeout=2)
  # utun and its point-to-point route disappear when ssocat closes the socket.
