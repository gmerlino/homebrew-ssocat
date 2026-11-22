import os,socket,struct,subprocess,time,pathlib,tempfile
root=pathlib.Path(__file__).parent
binary=os.environ.get('SSOCAT_TEST_BINARY','/opt/homebrew/bin/ssocat')
output=tempfile.TemporaryDirectory(prefix='ssocat-tcp-test-')
children=[]; sockets=[]; logs=[]
def start(address):
 a,b=socket.socketpair(socket.AF_UNIX,socket.SOCK_DGRAM); sockets.extend([a,b]); a.settimeout(5)
 env=dict(os.environ,DYLD_INSERT_LIBRARIES=os.environ.get('SSOCAT_TEST_SHIM',str(root/'mock_utun.dylib')),TEST_UTUN_FD=str(b.fileno()))
 log=open(pathlib.Path(output.name)/f'tcp-{len(children)}.log','w'); logs.append(log)
 p=subprocess.Popen([binary,'-d','-d','TUN,iff-no-pi,iff-slip',address],env=env,pass_fds=(b.fileno(),),stdout=log,stderr=log)
 children.append(p); return a

def packet(v):
 p=bytearray(64); p[0]=0x45 if v==4 else 0x60
 if v==4:p[2:4]=struct.pack('!H',len(p))
 else:p[4:6]=struct.pack('!H',len(p)-40)
 p[40:44]=b'\xc0\xdb\xc0\xdb'; return bytes(p)
def encode(p):return p.replace(b'\xdb',b'\xdb\xdd').replace(b'\xc0',b'\xdb\xdc')+b'\xc0'
def port():
 with socket.socket() as s:s.bind(('127.0.0.1',0));return s.getsockname()[1]
def connect(p):
 for _ in range(100):
  try:return socket.create_connection(('127.0.0.1',p),timeout=5)
  except ConnectionRefusedError:time.sleep(.02)
 raise RuntimeError('listener timeout')
try:
 p=port(); server=start(f'TCP-LISTEN:{p},bind=127.0.0.1,reuseaddr'); tcp=connect(p); sockets.append(tcp)
 for v in (4,6):
  data=packet(v); family=struct.pack('!I',socket.AF_INET if v==4 else socket.AF_INET6); wire=encode(data)
  for byte in wire:tcp.sendall(bytes([byte]));time.sleep(.001)
  assert server.recv(256)==family+data
  tcp.sendall(b'\xc0'+wire+wire)
  assert server.recv(256)==family+data; assert server.recv(256)==family+data
  server.send(family+data); got=b''
  while len(got)<len(wire):got+=tcp.recv(256)
  assert got==wire,(got,wire)
  print(f'PASS real TCP IPv{v}: bytewise fragmentation, coalescing, bidirectional SLIP',flush=True)
 p=port(); a=start(f'TCP-LISTEN:{p},bind=127.0.0.1,reuseaddr'); time.sleep(.3)
 b=start(f'TCP:127.0.0.1:{p}');time.sleep(.3)
 for v in (4,6):
  raw=struct.pack('!I',socket.AF_INET if v==4 else socket.AF_INET6)+packet(v)
  a.send(raw);assert b.recv(256)==raw
  b.send(raw);assert a.recv(256)==raw
  print(f'PASS two ssocat processes over TCP, IPv{v}, both directions',flush=True)
finally:
 for p in children:p.terminate()
 for p in children:p.wait(timeout=5)
 for s in sockets:s.close()
 for log in logs:log.close()

output.cleanup()
