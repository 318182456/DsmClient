import 'dart:convert';
import 'dart:io';
import 'package:dsm_client/util/dsm_compatibility.dart';

import 'package:dio/dio.dart';
import 'package:dsm_client/pages/setting/privacy.dart';
import 'package:dsm_client/pages/login/accounts.dart';
import 'package:dsm_client/pages/setting/license.dart';
import 'package:dsm_client/pages/update/update.dart';
import 'package:dsm_client/util/function.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:dsm_client/widgets/surfaces.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:flutter_vibrate/flutter_vibrate.dart';

class Login extends StatefulWidget {
  final Map server;
  final String type;
  Login({this.server, this.type = "login"});
  @override
  _LoginState createState() => _LoginState();
}

class _LoginState extends State<Login> {
  TapGestureRecognizer _licenseRecognizer = TapGestureRecognizer();
  TapGestureRecognizer _privacyRecognizer = TapGestureRecognizer();
  Map updateInfo;
  String host = "";
  String baseUrl = '';
  String account = "";
  String note = "";
  String password = "";
  String port = "5000";
  bool needOtp = false;
  String otpCode = "";
  String sid = "";
  String smid = "";
  bool https = false;
  bool login = false;
  bool rememberPassword = true;
  bool autoLogin = true;
  bool checkSsl = true;
  bool rememberDevice = false;
  bool read = false;
  TextEditingController _hostController = TextEditingController();
  TextEditingController _accountController = TextEditingController();
  TextEditingController _noteController = TextEditingController();
  TextEditingController _passwordController = TextEditingController();
  TextEditingController _portController = TextEditingController();
  TextEditingController _otpController = TextEditingController();
  List servers = [];
  List qcAddresses = [];
  CancelToken cancelToken = CancelToken();
  @override
  initState() {
    Util.getStorage("read").then((value) {
      if (value.isNotBlank && value == "1") {
        setState(() {
          read = true;
        });
      }
    });
    checkAgreement();
    if (Platform.isAndroid) {
      checkUpdate();
    } else {
      setState(() {
        read = true;
      });
    }
    Util.getStorage("servers").then((serverString) {
      if (serverString.isNotBlank) {
        servers = jsonDecode(serverString);
      }
      if (widget.server != null) {
        setState(() {
          https = widget.server['https'];
          host = widget.server['host'];
          port = widget.server['port'];
          account = widget.server['account'];
          note = widget.server['note'] ?? '';
          password = widget.server['password'];
          autoLogin = widget.server['auto_login'];
          rememberPassword = widget.server['remember_password'];
          checkSsl = widget.server['check_ssl'];
          if (host.isNotBlank) {
            _hostController.value = TextEditingValue(text: host);
          }
          if (port.isNotBlank) {
            _portController.value = TextEditingValue(text: port);
          }
          if (account.isNotBlank) {
            _accountController.value = TextEditingValue(text: account);
          }
          if (note.isNotBlank) {
            _noteController.value = TextEditingValue(text: note);
          }
          if (password.isNotBlank) {
            _passwordController.value = TextEditingValue(text: password);
          }
        });
        Util.cookie = widget.server['cookie'];
        Util.sid = widget.server['sid'];
        Util.sessionTokens.remember(widget.server['base_url'], Util.sid, widget.server['synotoken']);
        if (widget.server['action'] == "login") {
          _login();
        }
      } else {
        if (widget.type == "login") {
          getInfo();
        } else {
          _portController.value = TextEditingValue(text: port);
        }
      }
    });

    super.initState();
  }

  checkAgreement() async {
    String agreement = await Util.getStorage("agreement");
    if (agreement == null || agreement != '1') {
      showCupertinoDialog(
        context: context,
        builder: (context) {
          return Material(
            color: Colors.transparent,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                NeuCard(
                  width: double.infinity,
                  margin: EdgeInsets.symmetric(horizontal: 50),
                  curveType: CurveType.emboss,
                  bevel: 5,
                  decoration: NeumorphicDecoration(
                    color: Theme.of(context).scaffoldBackgroundColor,
                    borderRadius: BorderRadius.circular(25),
                  ),
                  child: Padding(
                    padding: EdgeInsets.all(20),
                    child: Column(
                      children: [
                        NeuCard(
                          decoration: NeumorphicDecoration(
                            color: Theme.of(context).scaffoldBackgroundColor,
                            borderRadius: BorderRadius.circular(20),
                          ),
                          bevel: 20,
                          curveType: CurveType.flat,
                          padding: EdgeInsets.symmetric(horizontal: 20, vertical: 5),
                          child: Text.rich(
                            TextSpan(
                              children: [
                                TextSpan(text: "欢迎使用${Util.appName}，请阅读本项目的"),
                                TextSpan(
                                  text: "开源许可",
                                  style: TextStyle(decoration: TextDecoration.underline, color: Colors.blue),
                                  recognizer: _licenseRecognizer
                                    ..onTap = () {
                                      FocusScope.of(context).unfocus();
                                      Navigator.of(context).push(CupertinoPageRoute(builder: (context) {
                                        return License();
                                      }));
                                    },
                                ),
                                TextSpan(text: " 和 "),
                                TextSpan(
                                  text: "隐私说明",
                                  style: TextStyle(decoration: TextDecoration.underline, color: Colors.blue),
                                  recognizer: _privacyRecognizer
                                    ..onTap = () {
                                      FocusScope.of(context).unfocus();
                                      Navigator.of(context).push(CupertinoPageRoute(builder: (context) {
                                        return Privacy();
                                      }));
                                    },
                                ),
                                TextSpan(text: "，了解许可条款及本机数据、NAS 连接和更新服务的数据流。\n"),
                                TextSpan(text: "在您使用${Util.appName}前，请务必仔细阅读"),
                                TextSpan(
                                  text: "开源许可",
                                  style: TextStyle(decoration: TextDecoration.underline, color: Colors.blue),
                                  recognizer: _licenseRecognizer
                                    ..onTap = () {
                                      FocusScope.of(context).unfocus();
                                      Navigator.of(context).push(CupertinoPageRoute(builder: (context) {
                                        return License();
                                      }));
                                    },
                                ),
                                TextSpan(text: "和 "),
                                TextSpan(
                                  text: "隐私说明",
                                  style: TextStyle(decoration: TextDecoration.underline, color: Colors.blue),
                                  recognizer: _privacyRecognizer
                                    ..onTap = () {
                                      FocusScope.of(context).unfocus();
                                      Navigator.of(context).push(CupertinoPageRoute(builder: (context) {
                                        return Privacy();
                                      }));
                                    },
                                ),
                                TextSpan(text: "以了解详细内容，如您同意，请点击'同意并继续'开始使用我们的服务"),
                              ],
                            ),
                          ),
                        ),
                        SizedBox(
                          height: 20,
                        ),
                        Row(
                          children: [
                            Expanded(
                              child: NeuButton(
                                onPressed: () async {
                                  Navigator.of(context).pop();
                                  Util.setStorage("read", "1");
                                  setState(() => read = true);
                                  Util.setStorage("agreement", "1");
                                },
                                decoration: NeumorphicDecoration(
                                  color: Theme.of(context).scaffoldBackgroundColor,
                                  borderRadius: BorderRadius.circular(25),
                                ),
                                bevel: 20,
                                padding: EdgeInsets.symmetric(vertical: 10),
                                child: Text(
                                  "同意并继续",
                                  style: TextStyle(fontSize: 18),
                                ),
                              ),
                            ),
                            SizedBox(
                              width: 16,
                            ),
                            Expanded(
                              child: NeuButton(
                                onPressed: () async {
                                  SystemNavigator.pop();
                                },
                                decoration: NeumorphicDecoration(
                                  color: Theme.of(context).scaffoldBackgroundColor,
                                  borderRadius: BorderRadius.circular(25),
                                ),
                                bevel: 20,
                                padding: EdgeInsets.symmetric(vertical: 10),
                                child: Text(
                                  "不同意",
                                  style: TextStyle(fontSize: 18),
                                ),
                              ),
                            ),
                          ],
                        )
                      ],
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      );
    }
  }

  @override
  void dispose() {
    _licenseRecognizer.dispose();
    _privacyRecognizer.dispose();
    super.dispose();
  }

  checkUpdate() async {
    if (Platform.isAndroid) {
      PackageInfo packageInfo = await PackageInfo.fromPlatform();
      String buildNumber = packageInfo.buildNumber;
      var res = await Api.update(buildNumber); //packageInfo.buildNumber
      if (res['code'] == 1 && mounted) {
        setState(() {
          updateInfo = res['data'];
        });
      }
    }
  }

  getInfo() async {
    sid = await Util.getStorage("sid");
    smid = await Util.getStorage("smid");
    String httpsString = await Util.getStorage("https");
    host = await Util.getStorage("host") ?? "";
    baseUrl = await Util.getStorage("base_url");
    String portString = await Util.getStorage("port");
    account = await Util.getStorage("account");
    note = await Util.getStorage("note");
    password = await Util.getStorage("password");
    String autoLoginString = await Util.getStorage("auto_login");

    String rememberPasswordString = await Util.getStorage("remember_password");
    String checkSslString = await Util.getStorage("check_ssl");
    Util.cookie = smid;
    Util.sessionTokens.remember(baseUrl, sid, await Util.getStorage('synotoken'));

    if (httpsString.isNotBlank) {
      setState(() {
        https = httpsString == "1";
      });
    }
    if (checkSslString.isNotBlank) {
      setState(() {
        checkSsl = checkSslString == "1";
      });
    }
    if (host.isNotBlank) {
      _hostController.value = TextEditingValue(text: host);
    }
    if (portString.isNotBlank) {
      port = portString;
      _portController.value = TextEditingValue(text: portString);
    } else {
      _portController.value = TextEditingValue(text: port);
    }
    if (account.isNotBlank) {
      _accountController.value = TextEditingValue(text: account);
    }
    if (note.isNotBlank) {
      _noteController.value = TextEditingValue(text: note);
    }
    if (password.isNotBlank) {
      _passwordController.value = TextEditingValue(text: password);
    }
    if (autoLoginString.isNotBlank) {
      setState(() {
        autoLogin = autoLoginString == "1";
      });
    }
    if (rememberPasswordString.isNotBlank) {
      setState(() {
        rememberPassword = rememberPasswordString == "1";
      });
    }
    checkLogin();
  }

  checkLogin() async {
    Util.account = account;
    if (https != null && sid.isNotBlank && host.isNotBlank) {
      if (baseUrl.isNotBlank) {
        Util.baseUrl = baseUrl;
      } else {
        Util.baseUrl = "${https ? "https" : "http"}://$host:$port";
      }
      //开始自动登录
      debugPrint("BaseUrl:$baseUrl");
      debugPrint("Util.BaseUrl:${Util.baseUrl}");
      Util.sid = sid;
      //如果开启了自动登录，则判断当前登录状态
      if (autoLogin) {
        setState(() {
          login = true;
        });
        var checkLogin = await Api.shareList(cancelToken: cancelToken);
        if (!checkLogin['success']) {
          if (checkLogin['code'] == "用户取消") {
            //如果用户主动取消登录
            setState(() {
              login = false;
            });
          } else {
            //如果登录失效，尝试重新登录
            debugPrint("尝试重新登录");
            _login();
          }
        } else {
          //登录有效，进入首页
          Navigator.of(context).pushNamedAndRemoveUntil("/home", (route) => false);
        }
      }
    }
  }

  _login() async {
    Util.checkSsl = checkSsl;
    FocusScope.of(context).unfocus();
    if (host.trim() == "") {
      Util.toast("请输入网址/IP/QuickConnect ID");
      return;
    }
    if (account == "") {
      Util.toast("请输入账号");
      return;
    }
    setState(() {
      login = true;
    });
    if (host.contains(".") || host.contains(':')) {
      String baseUri = "${https ? "https" : "http"}://${host.trim()}:${port.trim()}";
      debugPrint(baseUri);
      doLogin(baseUri);
    } else {
      // MagicDNS and LAN hostnames can be short names too, not only QuickConnect IDs.
      bool resolves = false;
      try {
        resolves = (await InternetAddress.lookup(host.trim())
          .timeout(Duration(seconds: 3))).isNotEmpty;
      } catch (_) {}
      if (!mounted) return;
      if (resolves) {
        doLogin("${https ? 'https' : 'http'}://${host.trim()}:${port.trim()}");
      } else {
        qcLogin();
      }
    }
  }

  qcLogin({String qcHost: "global.quickconnect.cn"}) async {
    debugPrint("QuickConnectID:$host");
    var res = await Api.quickConnect(host, baseUrl: qcHost);
    if (res['errno'] == 0) {
      if (res['server']['fqdn'] != "NULL") {
        qcAddresses.add("http://${res['server']['fqdn']}/");
      }
      if (res['server']['external']["ip"] != null) {
        qcAddresses.add("http://${res['server']['external']["ip"]}:${res['service']['ext_port']}/");
      }
      if (res['service']['relay_ip'] != null) {
        qcAddresses.add("http://${res['service']['relay_ip']}:${res['service']['relay_port']}/");
      }
      if (res['server']['ddns'] != "NULL") {
        qcAddresses.add("http://${res['server']['ddns']}:${res['service']['ext_port']}/");
      }
      if (res['server']['interface'].length > 0) {
        for (var interface in res['server']['interface']) {
          qcAddresses.add("http://${interface['ip']}:${res['service']['port']}/");
          if (interface['ipv6'].length > 0) {
            for (var v6 in interface['ipv6']) {
              qcAddresses.add("http://[${v6['address']}]:${res['service']['port']}/");
            }
          }
        }
      }
      if (res['service']['relay_ip'] == null) {
        var cnRes = await Api.quickConnectCn(host, baseUrl: res['env']['control_host']);
        if (cnRes['errno'] == 0) {
          if (cnRes['service']['relay_ip'] != null) {
            qcAddresses.add("http://${cnRes['service']['relay_ip']}:${cnRes['service']['relay_port']}/");
          }
        }
      }

      bool finded = false;
      for (var address in qcAddresses) {
        print(qcAddresses);
        Api.pingpong(address, (res) {
          if (res != null) {
            if (!finded) {
              setState(() {
                finded = true;
              });
              doLogin(res);
            }
          }
        });
      }
    } else if (res['errno'] == 4 && res['errinfo'].startsWith("get_server_info.go") && res['sites'].length > 0) {
      qcLogin(qcHost: res['sites'][0]);
    } else {
      Util.toast("无法连接到服务器，请检查QuickConnect ID是否正确");
      setState(() {
        login = false;
      });
    }
  }

  doLogin(String baseUri) async {
    var res = await Api.login(host: baseUri, account: account, password: password, otpCode: otpCode, cancelToken: cancelToken, rememberDevice: rememberDevice,
      cookie: widget.server != null ? widget.server['cookie'] :
        (DsmCompatibility.sameConnection(baseUri, Util.baseUrl) ? Util.cookie : ''),
      checkSsl: checkSsl);
    setState(() {
      login = false;
    });
    if (res['success'] == true) {
      //记住登录信息
      Util.account = account;
      Util.setStorage("https", https ? "1" : "0");
      Util.setStorage("host", host.trim());
      Util.setStorage("port", port);
      Util.setStorage("base_url", baseUri);
      Util.setStorage("account", account);
      Util.setStorage("note", note);
      Util.setStorage("remember_password", rememberPassword ? "1" : "0");
      Util.setStorage("auto_login", autoLogin ? "1" : "0");
      Util.setStorage("check_ssl", checkSsl ? "1" : "0");
      Util.sid = res['data']['sid'];
      Util.cookie = res['data']['cookie'] ?? '';
      Util.setStorage('smid', Util.cookie);
      Util.setStorage('synotoken', res['data']['synotoken'] ?? '');
      Api.apiList.clear();
      if (rememberPassword) {
        Util.setStorage("password", password);
      } else {
        Util.removeStorage("password");
      }
      if (autoLogin) {
        Util.setStorage("sid", res['data']['sid']);
      }

      Util.baseUrl = baseUri;

      //添加服务器记录
      bool exist = false;
      for (int i = 0; i < servers.length; i++) {
        if (servers[i]['https'] == https && servers[i]['host'] == host && servers[i]['port'] == port && servers[i]['account'] == account) {
          debugPrint("账号已存在，更新信息");
          if (rememberPassword) {
            servers[i]['password'] = password;
          } else {
            servers[i]['password'] = "";
          }

          servers[i]['remember_password'] = rememberPassword;
          servers[i]['note'] = note;
          servers[i]['auto_login'] = autoLogin;
          servers[i]['check_ssl'] = checkSsl;
          servers[i]['cookie'] = Util.cookie;
          servers[i]['sid'] = res['data']['sid'];
          servers[i]['synotoken'] = res['data']['synotoken'] ?? '';
          servers[i]['base_url'] = baseUri;
          exist = true;
        }
      }
      if (!exist) {
        debugPrint("账号不存在");
        Map server = {
          "https": https,
          "host": host,
          "base_url": baseUri,
          "port": port,
          "note": note,
          "account": account,
          "remember_password": rememberPassword,
          "auto_login": autoLogin,
          "check_ssl": checkSsl,
          "cookie": Util.cookie,
          "sid": res['data']['sid'],
          "synotoken": res['data']['synotoken'] ?? '',
        };
        if (rememberPassword) {
          server['password'] = password;
        } else {
          server['password'] = "";
        }
        servers.add(server);
      }
      Util.setStorage("servers", jsonEncode(servers));
      if (widget.type == "login") {
        Navigator.of(context).pushNamedAndRemoveUntil("/home", (route) => false);
      } else {
        Navigator.of(context).pop(true);
      }
    } else {
      Util.vibrate(FeedbackType.warning);
      if (res['error']['code'] == 400) {
        Util.toast("用户名/密码有误");
      } else if (res['error']['code'] == 403 || res['error']['code'] == 406) {
        Util.toast("请输入二次验证代码");
        setState(() {
          needOtp = true;
        });
      } else if (res['error']['code'] == 404) {
        _otpController.clear();
        Util.toast("错误的验证代码。请再试一次。");
      } else {
        Util.toast("登录失败，code:${res['error']['code']}");
      }
    }
  }

  // wakeup() async {
  //   print("wakeup");
  //   // final client = HttpDnsClient("http://180.76.76.76");
  //   // final result = await client.lookup("baidu.com");
  //   // print(result);
  //   String ipv4 = '192.168.0.100';
  //   IPv4Address ipv4Address;
  //   MACAddress macAddress;
  //   if (IPv4Address.validate(ipv4)) {
  //     ipv4Address = IPv4Address(ipv4);
  //     //Continue execution
  //   } else {
  //     Util.toast("IP地址有误");
  //     return;
  //     // Handle invalid address case
  //   }
  //   String mac = '02-11-32-27-31-2F';
  //   if (MACAddress.validate(mac)) {
  //     macAddress = MACAddress(mac);
  //     //Continue execution
  //   } else {
  //     Util.toast("MAC地址有误");
  //     return;
  //     // Handle invalid address case
  //   }
  //   WakeOnLAN wol = WakeOnLAN(ipv4Address, macAddress, port: 1234);
  //   await wol.wake().then((v) => print('sent'));
  // }

  void changeProtocol(bool value) {
    setState(() {
      https = value;
      if (https && port == '5000') port = '5001';
      else if (!https && port == '5001') port = '5000';
      _portController.text = port;
    });
  }

  Widget input(String key, TextEditingController controller, String label,
      {ValueChanged<String> onChanged, bool secret = false, TextInputType keyboard, List<TextInputFormatter> formatters, String hint}) {
    return TextField(key: ValueKey(key), controller: controller, enabled: !login, onChanged: onChanged,
      obscureText: secret, autocorrect: false, enableSuggestions: !secret,
      keyboardType: keyboard, inputFormatters: formatters, textInputAction: TextInputAction.next,
      style: Theme.of(context).textTheme.bodyText1.copyWith(fontSize:16,fontWeight:FontWeight.w400,height:1.3),
      decoration: InputDecoration(labelText:label,hintText:hint));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final showPort = host.contains('.') || host.contains(':');
    final protocol = DropdownButtonFormField<bool>(key:ValueKey('login-protocol'),value:https,isExpanded:true,
      decoration:InputDecoration(labelText:'连接协议'),items:[
        DropdownMenuItem(value:false,child:Text('HTTP')),DropdownMenuItem(value:true,child:Text('HTTPS'))],
      onChanged:login?null:changeProtocol);
    final portField = input('login-port',_portController,'端口',keyboard:TextInputType.number,
      formatters:[FilteringTextInputFormatter.digitsOnly,LengthLimitingTextInputFormatter(5)],onChanged:(v)=>port=v);
    final stackConnection = MediaQuery.of(context).size.width < 360 || MediaQuery.of(context).textScaleFactor > 1.3;
    return Scaffold(appBar: AppBar(title: Text(widget.type == 'login' ? '账号登录' : '添加账号'), actions: [
      if (updateInfo != null) IconButton(tooltip:'软件更新', icon:Icon(Icons.system_update_outlined), onPressed:()=>
        Navigator.push(context,CupertinoPageRoute(builder:(_)=>Update(updateInfo)))),
      if (servers.isNotEmpty) IconButton(tooltip:'已保存的账号',icon:Icon(Icons.history),onPressed:()=>
        Navigator.push(context,CupertinoPageRoute(builder:(_)=>Accounts()))),
    ]), body: SafeArea(top:false,child:GestureDetector(onTap:()=>FocusScope.of(context).unfocus(),
      child:ListView(padding:EdgeInsets.fromLTRB(20,24,20,28),children:[
        Text('连接你的 NAS',style:theme.textTheme.headline5),SizedBox(height:6),
        Text('输入服务器地址和 DSM 账号。',style:theme.textTheme.caption),SizedBox(height:28),
        input('login-host',_hostController,'NAS 地址',keyboard:TextInputType.url,hint:'IP、域名或 QuickConnect ID',
          onChanged:(v)=>setState(()=>host=v)),SizedBox(height:18),
        if(stackConnection) Column(children:[protocol,if(showPort)...[SizedBox(height:18),portField]])
        else Row(crossAxisAlignment:CrossAxisAlignment.start,children:[Expanded(child:protocol),
          if(showPort)...[SizedBox(width:14),Expanded(child:portField)]]),
        SizedBox(height:18),
        input('login-account',_accountController,'账号',onChanged:(v)=>account=v),SizedBox(height:18),
        input('login-password',_passwordController,'密码',secret:true,onChanged:(v)=>password=v),SizedBox(height:18),
        input('login-note',_noteController,'备注（可选）',onChanged:(v)=>note=v),SizedBox(height:22),
        if(needOtp)...[
          input('login-otp',_otpController,'二步验证代码',keyboard:TextInputType.number,onChanged:(v)=>otpCode=v),SizedBox(height:18),
        ],
        Card(child:Column(children:[
          SwitchListTile.adaptive(title:Text('记住密码'),value:rememberPassword,onChanged:login?null:(v)=>setState((){
            rememberPassword=v;if(!v)autoLogin=false;
          })),
          Divider(height:1,indent:16,endIndent:16),
          SwitchListTile.adaptive(title:Text('自动登录'),value:autoLogin,onChanged:login?null:(v)=>setState((){
            autoLogin=v;if(v)rememberPassword=true;
          })),
          if(https)...[Divider(height:1,indent:16,endIndent:16),
            SwitchListTile.adaptive(title:Text('验证 SSL 证书'),value:checkSsl,onChanged:login?null:(v)=>setState(()=>checkSsl=v))],
          if(needOtp)...[Divider(height:1,indent:16,endIndent:16),
            SwitchListTile.adaptive(title:Text('记住设备'),value:rememberDevice,onChanged:login?null:(v)=>setState(()=>rememberDevice=v))],
        ])),SizedBox(height:12),
        ElevatedButton(key:ValueKey('login-submit'),onPressed:(){
          FocusScope.of(context).unfocus();
          if(login){cancelToken?.cancel('取消登录');cancelToken=CancelToken();setState(()=>login=false);return;}
          if(!read){Util.toast('请先阅读并同意开源许可和隐私说明');return;}
          _login();
        },child:login?Row(mainAxisAlignment:MainAxisAlignment.center,children:[
          SizedBox(width:18,height:18,child:CircularProgressIndicator(strokeWidth:2,color:theme.colorScheme.onPrimary)),
          SizedBox(width:10),Text('取消登录')]):Text(widget.type=='login'?'登录':'添加账号')),
        SizedBox(height:14),
        Row(crossAxisAlignment:CrossAxisAlignment.start,children:[
          SizedBox(width:36,height:40,child:Checkbox(value:read,onChanged:login?null:(v)=>setState((){
            read=v==true;Util.setStorage('read',read?'1':'0');
          }))),SizedBox(width:4),
          Expanded(child:Padding(padding:EdgeInsets.only(top:10),child:Text.rich(TextSpan(
            style:theme.textTheme.caption,children:[TextSpan(text:'我已阅读并同意 DsmClient '),
            TextSpan(text:'开源许可',style:TextStyle(color:theme.colorScheme.primary,decoration:TextDecoration.underline),
              recognizer:_licenseRecognizer..onTap=()=>Navigator.push(context,CupertinoPageRoute(builder:(_)=>License()))),
            TextSpan(text:'和'),TextSpan(text:'隐私说明',style:TextStyle(color:theme.colorScheme.primary,decoration:TextDecoration.underline),
              recognizer:_privacyRecognizer..onTap=()=>Navigator.push(context,CupertinoPageRoute(builder:(_)=>Privacy()))),
          ])))),
        ]),
      ]))));
  }
}
