import 'package:flutter/material.dart';
import 'package:whispering_time/design/widgets.dart';
import 'package:whispering_time/page/home/appbar.dart';
import 'package:whispering_time/service/http/official.dart';
import 'package:whispering_time/service/isar/config.dart';
import 'package:whispering_time/service/sp/sp.dart';
import 'package:whispering_time/util/secure.dart';
import 'package:whispering_time/util/ui.dart';

class Welcome extends StatefulWidget {
  const Welcome({super.key});

  @override
  State<Welcome> createState() => _Welcome();
}

class _Welcome extends State<Welcome> {
  final userController = TextEditingController();
  final emailController = TextEditingController();
  final accountController = TextEditingController();
  final passwordController = TextEditingController();
  final registerPasswordController = TextEditingController();
  final passwordAgainController = TextEditingController();
  final _scrollController = ScrollController();
  final _loginFormKey = GlobalKey<FormState>();
  final _registerFormKey = GlobalKey<FormState>();
  final _accountFocus = FocusNode();
  final _passwordFocus = FocusNode();
  final _userFocus = FocusNode();
  final _emailFocus = FocusNode();
  final _registerPasswordFocus = FocusNode();
  final _passwordAgainFocus = FocusNode();

  bool _showLogin = false;
  bool _isRegister = false;
  bool isAutoLogin = false;
  bool _isSubmitting = false;
  bool _hideLoginPassword = true;
  bool _hideRegisterPassword = true;
  bool _hideConfirmationPassword = true;
  String? _submissionError;

  @override
  void dispose() {
    _scrollController.dispose();
    userController.dispose();
    emailController.dispose();
    accountController.dispose();
    passwordController.dispose();
    registerPasswordController.dispose();
    passwordAgainController.dispose();
    _accountFocus.dispose();
    _passwordFocus.dispose();
    _userFocus.dispose();
    _emailFocus.dispose();
    _registerPasswordFocus.dispose();
    _passwordAgainFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_showLogin,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop && !_isSubmitting) {
          _backFromForm();
        }
      },
      child: Scaffold(
        body: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final isWide = constraints.maxWidth >= 960;
              final padding = constraints.maxWidth < 600 ? 24.0 : 48.0;
              return SingleChildScrollView(
                controller: _scrollController,
                keyboardDismissBehavior:
                    ScrollViewKeyboardDismissBehavior.onDrag,
                padding: EdgeInsets.all(padding),
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    minHeight: (constraints.maxHeight - padding * 2).clamp(
                      0.0,
                      double.infinity,
                    ),
                  ),
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 1120),
                      child: isWide
                          ? Row(
                              crossAxisAlignment: CrossAxisAlignment.center,
                              children: [
                                Expanded(child: _buildBrandSection(isWide)),
                                const SizedBox(width: 48),
                                Flexible(child: _buildFormArea()),
                              ],
                            )
                          : Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                _buildBrandSection(isWide),
                                const SizedBox(height: 32),
                                _buildFormArea(),
                              ],
                            ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildBrandSection(bool isWide) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final alignment = isWide
        ? CrossAxisAlignment.start
        : CrossAxisAlignment.center;
    final textAlign = isWide ? TextAlign.start : TextAlign.center;
    final compact = !isWide && _showLogin;

    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 480),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: alignment,
        children: [
          ExcludeSemantics(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(24),
              child: Image.asset(
                'assets/images/icon.png',
                width: compact ? 64 : 96,
                height: compact ? 64 : 96,
                fit: BoxFit.contain,
              ),
            ),
          ),
          const SizedBox(height: 24),
          Semantics(
            header: true,
            child: Text(
              '枫迹',
              style: theme.textTheme.headlineLarge,
              textAlign: textAlign,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            '生活不只是日复一日，\n更是步步印迹。',
            textAlign: textAlign,
            style: theme.textTheme.titleLarge?.copyWith(
              color: colors.onSurfaceVariant,
              height: 1.6,
            ),
          ),
          if (isWide) ...[
            const SizedBox(height: 48),
            _buildFeature(Icons.edit_note_outlined, '随手记录', '把想法与日常，留在文字里。'),
            const SizedBox(height: 24),
            _buildFeature(Icons.folder_outlined, '有序整理', '让每一份文档，都有自己的位置。'),
          ],
        ],
      ),
    );
  }

  Widget _buildFeature(IconData icon, String title, String description) {
    final theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ExcludeSemantics(
          child: Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Icon(icon, color: theme.colorScheme.primary, size: 24),
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: theme.textTheme.titleMedium),
              const SizedBox(height: 4),
              Text(
                description,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildFormArea() {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 440),
      child: ImprintPanel(
        padding: const EdgeInsets.all(24),
        child: FocusTraversalGroup(
          child: _showLogin
              ? (_isRegister ? registerForm() : loginForm())
              : accountType(),
        ),
      ),
    );
  }

  Widget _heading(String title, String subtitle, {bool withBack = false}) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (withBack) ...[
          TextButton.icon(
            onPressed: _isSubmitting ? null : _backFromForm,
            icon: const Icon(Icons.arrow_back_rounded, size: 20),
            label: const Text('返回'),
          ),
          const SizedBox(height: 12),
        ],
        Semantics(
          header: true,
          child: Text(title, style: theme.textTheme.headlineSmall),
        ),
        const SizedBox(height: 8),
        Text(
          subtitle,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 24),
      ],
    );
  }

  Widget accountType() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _heading('留住今天的印迹', '从一段文字开始，慢慢收集生活。'),
        _primaryButton(
          label: '游客访问',
          loadingLabel: '正在进入…',
          icon: Icons.explore_outlined,
          onPressed: visitor,
        ),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: _isSubmitting
              ? null
              : () => _changeForm(showLogin: true, register: false),
          icon: const Icon(Icons.person_outline_rounded, size: 20),
          label: const Text('账号登陆'),
        ),
        const SizedBox(height: 24),
        Text(
          '游客模式不支持多端数据共享。',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodySmall
              ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
        ),
        const SizedBox(height: 8),
        TextButton.icon(
          onPressed: _showVisitorInformation,
          icon: const Icon(Icons.info_outline_rounded, size: 20),
          label: const Text('了解更多'),
        ),
        if (_submissionError != null) ...[
          const SizedBox(height: 16),
          _errorMessage(),
        ],
      ],
    );
  }

  Widget loginForm() {
    return Form(
      key: _loginFormKey,
      child: AutofillGroup(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _heading('欢迎回来', '登录账号，继续记录与整理。', withBack: true),
            TextFormField(
              autofocus: true,
              enabled: !_isSubmitting,
              controller: accountController,
              focusNode: _accountFocus,
              decoration: const InputDecoration(
                labelText: '用户名 / 邮箱',
                prefixIcon: Icon(Icons.person_outline_rounded),
              ),
              autofillHints: const [AutofillHints.username],
              textInputAction: TextInputAction.next,
              validator: (value) =>
                  value == null || value.isEmpty ? '用户名不能为空' : null,
            ),
            const SizedBox(height: 16),
            TextFormField(
              enabled: !_isSubmitting,
              controller: passwordController,
              focusNode: _passwordFocus,
              decoration: InputDecoration(
                labelText: '密码',
                prefixIcon: const Icon(Icons.lock_outline_rounded),
                suffixIcon: _passwordToggle(
                  hidden: _hideLoginPassword,
                  onPressed: () =>
                      setState(() => _hideLoginPassword = !_hideLoginPassword),
                ),
              ),
              autofillHints: const [AutofillHints.password],
              textInputAction: TextInputAction.done,
              obscureText: _hideLoginPassword,
              enableSuggestions: false,
              autocorrect: false,
              validator: (value) =>
                  value == null || value.isEmpty ? '密码不能为空' : null,
              onFieldSubmitted: (_) => login(),
            ),
            const SizedBox(height: 12),
            CheckboxListTile(
              value: isAutoLogin,
              onChanged: _isSubmitting
                  ? null
                  : (value) => setState(() => isAutoLogin = value ?? false),
              title: const Text('自动登录'),
              controlAffinity: ListTileControlAffinity.leading,
              contentPadding: EdgeInsets.zero,
            ),
            const SizedBox(height: 16),
            if (_submissionError != null) ...[
              _errorMessage(),
              const SizedBox(height: 16),
            ],
            _primaryButton(
              label: '登录',
              loadingLabel: '正在登录…',
              icon: Icons.arrow_forward_rounded,
              onPressed: login,
            ),
            const SizedBox(height: 16),
            Wrap(
              alignment: WrapAlignment.spaceBetween,
              spacing: 8,
              runSpacing: 8,
              children: [
                TextButton(
                  onPressed: _isSubmitting ? null : visitor,
                  child: const Text('游客登陆'),
                ),
                TextButton(
                  onPressed: _isSubmitting
                      ? null
                      : () => _changeForm(showLogin: true, register: true),
                  child: const Text('注册账号'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget registerForm() {
    return Form(
      key: _registerFormKey,
      child: AutofillGroup(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _heading('创建账号', '让生活的片段，有一处安放。', withBack: true),
            TextFormField(
              autofocus: true,
              enabled: !_isSubmitting,
              controller: userController,
              focusNode: _userFocus,
              decoration: const InputDecoration(
                labelText: '用户名',
                helperText: '3–20 个字符，可使用字母、数字、下划线和点',
                helperMaxLines: 3,
                prefixIcon: Icon(Icons.person_outline_rounded),
              ),
              autofillHints: const [AutofillHints.newUsername],
              textInputAction: TextInputAction.next,
              validator: _userError,
            ),
            const SizedBox(height: 16),
            TextFormField(
              enabled: !_isSubmitting,
              controller: emailController,
              focusNode: _emailFocus,
              decoration: const InputDecoration(
                labelText: '邮箱',
                prefixIcon: Icon(Icons.mail_outline_rounded),
              ),
              autofillHints: const [AutofillHints.email],
              keyboardType: TextInputType.emailAddress,
              textInputAction: TextInputAction.next,
              autocorrect: false,
              validator: _emailError,
            ),
            const SizedBox(height: 16),
            TextFormField(
              enabled: !_isSubmitting,
              controller: registerPasswordController,
              focusNode: _registerPasswordFocus,
              decoration: InputDecoration(
                labelText: '密码',
                helperText: '至少 8 个字符，包含大写、小写字母和数字',
                helperMaxLines: 3,
                prefixIcon: const Icon(Icons.lock_outline_rounded),
                suffixIcon: _passwordToggle(
                  hidden: _hideRegisterPassword,
                  onPressed: () => setState(
                    () => _hideRegisterPassword = !_hideRegisterPassword,
                  ),
                ),
              ),
              autofillHints: const [AutofillHints.newPassword],
              textInputAction: TextInputAction.next,
              obscureText: _hideRegisterPassword,
              enableSuggestions: false,
              autocorrect: false,
              validator: _registerPasswordError,
            ),
            const SizedBox(height: 16),
            TextFormField(
              enabled: !_isSubmitting,
              controller: passwordAgainController,
              focusNode: _passwordAgainFocus,
              decoration: InputDecoration(
                labelText: '再次输入密码',
                prefixIcon: const Icon(Icons.lock_outline_rounded),
                suffixIcon: _passwordToggle(
                  hidden: _hideConfirmationPassword,
                  onPressed: () => setState(
                    () =>
                        _hideConfirmationPassword = !_hideConfirmationPassword,
                  ),
                ),
              ),
              autofillHints: const [AutofillHints.newPassword],
              textInputAction: TextInputAction.done,
              obscureText: _hideConfirmationPassword,
              enableSuggestions: false,
              autocorrect: false,
              validator: (value) =>
                  value != registerPasswordController.text ? '密码不一致' : null,
              onFieldSubmitted: (_) => register(),
            ),
            const SizedBox(height: 24),
            if (_submissionError != null) ...[
              _errorMessage(),
              const SizedBox(height: 16),
            ],
            _primaryButton(
              label: '注册',
              loadingLabel: '正在注册…',
              icon: Icons.person_add_alt_rounded,
              onPressed: register,
            ),
            const SizedBox(height: 16),
            TextButton(
              onPressed: _isSubmitting
                  ? null
                  : () => _changeForm(showLogin: true, register: false),
              child: const Text('已有账号，登录'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _passwordToggle({
    required bool hidden,
    required VoidCallback onPressed,
  }) {
    return IconButton(
      onPressed: _isSubmitting ? null : onPressed,
      tooltip: hidden ? '显示密码' : '隐藏密码',
      icon: Icon(
        hidden ? Icons.visibility_outlined : Icons.visibility_off_outlined,
      ),
    );
  }

  Widget _primaryButton({
    required String label,
    required String loadingLabel,
    required IconData icon,
    required VoidCallback onPressed,
  }) {
    return FilledButton.icon(
      onPressed: _isSubmitting ? null : onPressed,
      icon: _isSubmitting
          ? const SizedBox.square(
              dimension: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : Icon(icon, size: 20),
      label: Text(_isSubmitting ? loadingLabel : label),
    );
  }

  Widget _errorMessage() {
    final colors = Theme.of(context).colorScheme;
    return Semantics(
      liveRegion: true,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: colors.errorContainer,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ExcludeSemantics(
              child: Icon(
                Icons.error_outline_rounded,
                color: colors.onErrorContainer,
                size: 20,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                _submissionError!,
                style: Theme.of(context).textTheme.bodyMedium
                    ?.copyWith(color: colors.onErrorContainer),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _backFromForm() => _changeForm(showLogin: _isRegister, register: false);

  void _changeForm({required bool showLogin, required bool register}) {
    FocusScope.of(context).unfocus();
    setState(() {
      _showLogin = showLogin;
      _isRegister = register;
      _submissionError = null;
    });
    if (_scrollController.hasClients) {
      _scrollController.jumpTo(0);
    }
  }

  void _showVisitorInformation() {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('游客模式说明'),
        content: const SingleChildScrollView(
          child: Text('游客模式下，无法提交反馈且不支持多端数据共享。'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('知道了'),
          ),
        ],
      ),
    );
  }

  void _beginSubmission() {
    FocusScope.of(context).unfocus();
    setState(() {
      _isSubmitting = true;
      _submissionError = null;
    });
  }

  void _endSubmission() {
    if (mounted) {
      setState(() => _isSubmitting = false);
    }
  }

  void _failSubmission(String message) {
    if (mounted) {
      setState(() => _submissionError = message);
    }
  }

  void _openHome() {
    if (mounted) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (context) => HomePage()),
      );
    }
  }

  // 保留原有游客账号恢复、注册和本地配置语义。
  Future<void> visitor() async {
    if (_isSubmitting) return;
    _beginSubmission();
    try {
      final confirmed = await showConfirmationDialog(
        context,
        MyDialog(content: '是否以游客身份登陆？'),
      );
      if (!confirmed || !mounted) return;
      final oldVisitorId = SP().getVisitorUID();
      final isVisitorLogged = SP().getIsVisitorLogged();
      if (isVisitorLogged && oldVisitorId.isNotEmpty) {
        await Config().init(oldVisitorId);
        _openHome();
        return;
      }
      final value = await Http().userRegisterVisitor();
      if (value.isNotOK) {
        _failSubmission('游客访问未完成，请稍后重试。');
        return;
      }
      if (value.id.isEmpty) {
        _failSubmission('用户不存在');
        return;
      }
      SP().setIsVisitor(true);
      SP().setVisitorUID(value.id);
      SP().setIsVisitorLogged(true);
      await Config().init(value.id);
      _openHome();
    } catch (_) {
      _failSubmission('游客访问未完成，请稍后重试。');
    } finally {
      _endSubmission();
    }
  }

  bool loginCheck() {
    final valid = _loginFormKey.currentState?.validate() ?? false;
    if (!valid) {
      if (accountController.text.isEmpty) {
        _accountFocus.requestFocus();
      } else {
        _passwordFocus.requestFocus();
      }
    }
    return valid;
  }

  Future<void> login() async {
    if (_isSubmitting || !loginCheck()) return;
    final account = accountController.text;
    final password = passwordController.text;
    _beginSubmission();
    try {
      final value = await Http().userLogin(
        RequestUserLogin(account: account, password: password),
      );
      final loginUserId = value.id;
      if (!value.isOK) {
        _failSubmission('登录未完成，请检查账号信息后重试。');
        return;
      }
      if (loginUserId.isEmpty) {
        _failSubmission('用户不存在');
        return;
      }
      SP().setIsVisitor(false);
      SP().setUID(loginUserId);
      SP().setIsVisitorLogged(false);
      SP().setIsAutoLogin(isAutoLogin);
      await Config().init(loginUserId);
      Config.instance.setAPIs(value.apis);
      _openHome();
    } catch (_) {
      _failSubmission('登录未完成，请稍后重试。');
    } finally {
      _endSubmission();
    }
  }

  String? _registerPasswordError(String? value) {
    final password = value ?? '';
    if (password.isEmpty) return '密码不能为空';
    if (password.length < 8) return '密码长度不能少于 8 个字符';
    if (!password.contains(RegExp(r'[A-Z]'))) {
      return '密码需要包含至少一个大写字母';
    }
    if (!password.contains(RegExp(r'[a-z]'))) {
      return '密码需要包含至少一个小写字母';
    }
    // 本次仅调整界面，沿用既有数字校验规则。
    if (!password.contains(RegExp(r''))) {
      return '密码需要包含至少一个数字';
    }
    return null;
  }

  String? _userError(String? value) {
    final username = value ?? '';
    if (username.isEmpty) return '用户名不能为空';
    if (username.length < 3) return '用户名长度不能少于 3 个字符';
    if (username.length > 20) return '用户名长度不能超过 20 个字符';
    if (!RegExp(r'^[a-zA-Z0-9_.]+$').hasMatch(username)) {
      return '用户名只能包含字母、数字、下划线和点';
    }
    if (RegExp(r'^[0-9]+$').hasMatch(username) && username.length < 6) {
      return '不允许过于简单的纯数字用户名';
    }
    const forbiddenWords = [
      'admin',
      'test',
      'guest',
      'root',
      'administrator',
      'administrators',
      'superuser',
    ];
    if (forbiddenWords.contains(username.toLowerCase())) {
      return '该用户名已被禁用';
    }
    return null;
  }

  String? _emailError(String? value) {
    final email = value ?? '';
    if (email.isEmpty) return '邮箱不能为空';
    if (!RegExp(r'^\w+([-+.]\w+)*@\w+([-.]\w+)*\.\w+([-.]\w+)*$')
        .hasMatch(email)) {
      return '邮箱格式不正确';
    }
    return null;
  }

  bool registerCheck() {
    final valid = _registerFormKey.currentState?.validate() ?? false;
    if (!valid) {
      if (_userError(userController.text) != null) {
        _userFocus.requestFocus();
      } else if (_emailError(emailController.text) != null) {
        _emailFocus.requestFocus();
      } else if (_registerPasswordError(registerPasswordController.text) !=
          null) {
        _registerPasswordFocus.requestFocus();
      } else {
        _passwordAgainFocus.requestFocus();
      }
    }
    return valid;
  }

  Future<void> register() async {
    if (_isSubmitting || !registerCheck()) return;
    final user = userController.text;
    final email = emailController.text;
    final password = registerPasswordController.text;
    _beginSubmission();
    try {
      final publicKey = await generateKey();
      if (!mounted) return;
      final value = await Http().userRegister(
        RequestCreateUserRegister(
          username: user,
          email: email,
          password: password,
          publicKey: publicKey,
        ),
      );
      final registerUserId = value.id;
      if (!value.isOK) {
        _failSubmission('注册未完成，请检查填写的信息后重试。');
        return;
      }
      if (registerUserId.isEmpty) {
        _failSubmission('用户不存在');
        return;
      }
      SP().setIsVisitor(false);
      SP().setUID(registerUserId);
      SP().setIsVisitorLogged(false);
      await Config().init(registerUserId);
      _openHome();
    } catch (_) {
      _failSubmission('注册未完成，请稍后重试。');
    } finally {
      _endSubmission();
    }
  }

  Future<List<int>> generateKey() async {
    final key = await KeyManager.generateX25519();
    await Storage().getKey(newKey: key.privateKey);
    return key.publicKey;
  }
}
