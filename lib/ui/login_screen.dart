import 'dart:async';

import 'package:flutter/material.dart';
import 'package:ncm_api/ncm_api.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../services/app_state.dart';

/// Login screen offering two flows via a [TabBar]: QR-code scan and
/// phone + password/captcha. Pops `true` on successful login.
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('登录'),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: '扫码登录', icon: Icon(Icons.qr_code)),
            Tab(text: '手机登录', icon: Icon(Icons.phone_android)),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: const [
          _QrLoginTab(),
          _PhoneLoginTab(),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// QR login
// ---------------------------------------------------------------------------

class _QrLoginTab extends StatefulWidget {
  const _QrLoginTab();

  @override
  State<_QrLoginTab> createState() => _QrLoginTabState();
}

class _QrLoginTabState extends State<_QrLoginTab> {
  Timer? _timer;
  String? _qrUrl;
  String _hint = '正在生成二维码…';
  bool _loading = true;
  bool _expired = false;

  @override
  void initState() {
    super.initState();
    _generate();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _generate() async {
    _timer?.cancel();
    setState(() {
      _loading = true;
      _expired = false;
      _hint = '正在生成二维码…';
      _qrUrl = null;
    });

    final client = context.read<AppState>().client;
    try {
      final unikey = await client.loginQrKey();
      if (!mounted) return;
      final url = client.loginQrCodeUrl(unikey);
      setState(() {
        _qrUrl = url;
        _loading = false;
        _hint = '请使用网易云音乐App扫码';
      });
      _startPolling(unikey);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _hint = e.message;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _hint = '二维码生成失败';
      });
    }
  }

  void _startPolling(String unikey) {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 2), (_) => _poll(unikey));
  }

  Future<void> _poll(String unikey) async {
    final client = context.read<AppState>().client;
    ApiResponse resp;
    try {
      resp = await client.loginQrCheck(unikey);
    } catch (_) {
      return;
    }
    if (!mounted) return;

    final code = resp.body['code'];
    switch (code) {
      case 801:
        setState(() => _hint = '请使用网易云音乐App扫码');
        break;
      case 802:
        setState(() => _hint = '已扫描，请在手机上确认');
        break;
      case 800:
        _timer?.cancel();
        setState(() {
          _hint = '二维码已过期';
          _expired = true;
        });
        break;
      case 803:
        _timer?.cancel();
        await context.read<AppState>().onLoggedIn();
        if (!mounted) return;
        if (context.mounted) {
          Navigator.of(context).pop(true);
        }
        break;
      default:
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_loading)
              const SizedBox(
                width: 220,
                height: 220,
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_qrUrl != null)
              Container(
                padding: const EdgeInsets.all(12),
                color: Colors.white,
                child: QrImageView(data: _qrUrl!, size: 220),
              )
            else
              Container(
                width: 220,
                height: 220,
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                child: const Icon(Icons.qr_code_2, size: 96),
              ),
            const SizedBox(height: 24),
            Text(
              _hint,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyLarge,
            ),
            if (_expired) ...[
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: _generate,
                icon: const Icon(Icons.refresh),
                label: const Text('刷新二维码'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Phone login
// ---------------------------------------------------------------------------

class _PhoneLoginTab extends StatefulWidget {
  const _PhoneLoginTab();

  @override
  State<_PhoneLoginTab> createState() => _PhoneLoginTabState();
}

class _PhoneLoginTabState extends State<_PhoneLoginTab> {
  final _phoneController = TextEditingController();
  final _passwordController = TextEditingController();
  final _captchaController = TextEditingController();

  bool _useCaptcha = false;
  bool _submitting = false;
  bool _sendingCaptcha = false;

  @override
  void dispose() {
    _phoneController.dispose();
    _passwordController.dispose();
    _captchaController.dispose();
    super.dispose();
  }

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _sendCaptcha() async {
    final phone = _phoneController.text.trim();
    if (phone.isEmpty) {
      _snack('请输入手机号');
      return;
    }
    setState(() => _sendingCaptcha = true);
    final client = context.read<AppState>().client;
    try {
      await client.sendCaptcha(phone);
      if (!mounted) return;
      setState(() => _useCaptcha = true);
      _snack('验证码已发送');
    } on ApiException catch (e) {
      _snack(e.message);
    } finally {
      if (mounted) setState(() => _sendingCaptcha = false);
    }
  }

  Future<void> _login() async {
    final phone = _phoneController.text.trim();
    if (phone.isEmpty) {
      _snack('请输入手机号');
      return;
    }
    final password = _passwordController.text;
    final captcha = _captchaController.text.trim();

    if (_useCaptcha && captcha.isEmpty) {
      _snack('请输入验证码');
      return;
    }
    if (!_useCaptcha && password.isEmpty) {
      _snack('请输入密码');
      return;
    }

    setState(() => _submitting = true);
    final client = context.read<AppState>().client;
    try {
      final body = await client.loginCellphone(
        phone: phone,
        password: _useCaptcha ? null : password,
        captcha: _useCaptcha ? captcha : null,
      );
      if (!mounted) return;
      if (body['code'] == 200) {
        await context.read<AppState>().onLoggedIn();
        if (!mounted) return;
        if (context.mounted) {
          Navigator.of(context).pop(true);
        }
      } else {
        _snack((body['message'] ?? '登录失败').toString());
      }
    } on ApiException catch (e) {
      _snack(e.message);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: _phoneController,
            keyboardType: TextInputType.phone,
            decoration: const InputDecoration(
              labelText: '手机号',
              prefixIcon: Icon(Icons.phone),
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 16),
          if (_useCaptcha)
            TextField(
              controller: _captchaController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: '验证码',
                prefixIcon: Icon(Icons.sms),
                border: OutlineInputBorder(),
              ),
            )
          else
            TextField(
              controller: _passwordController,
              obscureText: true,
              decoration: const InputDecoration(
                labelText: '密码',
                prefixIcon: Icon(Icons.lock),
                border: OutlineInputBorder(),
              ),
            ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: _sendingCaptcha ? null : _sendCaptcha,
                  child: _sendingCaptcha
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('发送验证码'),
                ),
              ),
              if (_useCaptcha) ...[
                const SizedBox(width: 12),
                TextButton(
                  onPressed: () => setState(() => _useCaptcha = false),
                  child: const Text('用密码登录'),
                ),
              ],
            ],
          ),
          const SizedBox(height: 24),
          FilledButton(
            onPressed: _submitting ? null : _login,
            child: _submitting
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('登录'),
          ),
        ],
      ),
    );
  }
}
