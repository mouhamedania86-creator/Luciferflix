import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'strings.dart';
import 'user_data.dart';

/// ====== البروفايلات (NetFlix style) ======
///
/// كل بروفايل له قائمته وتقييماته وتخطياته وإعداداته. يمكن وضع رمز سري
/// (4 أرقام) على أي بروفايل — هذا هو "الرقابة parental".

class ProfileScreen extends StatefulWidget {
  final bool pickerMode; // true = اختيار بروفايل، false = إدارة البروفايلات
  const ProfileScreen({super.key, this.pickerMode = false});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  List<Profile> _profiles = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final p = await UD.profiles();
    if (!mounted) return;
    setState(() {
      _profiles = p;
      _loading = false;
    });
  }

  Future<void> _pick(Profile p) async {
    if (!await _authorizeKidEscape()) return;
    if (p.pin != null) {
      final ok = await showPinDialog(context, expected: p.pin);
      if (ok != true) return;
    }
    await UD.setActive(p.id);
    await UD.setSetting('kidsMode', p.isKid);
    if (!mounted) return;
    if (widget.pickerMode) {
      Navigator.of(context).pop();
    } else {
      setState(() {});
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${S.t('active_profile')}: ${p.name}')),
      );
    }
  }

  Future<void> _create() async {
    if (!await _authorizeKidEscape()) return;
    if (!mounted) return;
    final res = await showDialog<_ProfileForm>(
      context: context,
      builder: (_) => const _ProfileEditorDialog(),
    );
    if (res == null) return;
    await UD.createProfile(
      name: res.name,
      avatar: res.avatar,
      isKid: res.isKid,
      pin: res.pin,
    );
    await _load();
  }

  /// A child profile cannot escape to another profile or create one unless
  /// an adult enters the PIN of any PIN-protected profile.
  Future<bool> _authorizeKidEscape() async {
    final active = await UD.activeProfileObj();
    if (!active.isKid) return true;
    final all = await UD.profiles();
    Profile? locked;
    for (final profile in all) {
      if (profile.pin != null) {
        locked = profile;
        break;
      }
    }
    if (!mounted) return false;
    if (locked == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('لا يمكن تغيير البروفايل من وضع الأطفال: ما كاين حتى بروفايل محمي بـ PIN.'),
        ),
      );
      return false;
    }
    final ok = await showPinDialog(context, expected: locked.pin);
    return ok == true;
  }

  Future<bool> _authorizeProfileChange(Profile p) async {
    // A PIN-protected profile cannot be edited or deleted without its PIN.
    if (p.pin == null) return true;
    final ok = await showPinDialog(context, expected: p.pin);
    return ok == true;
  }

  Future<void> _edit(Profile p) async {
    if (!await _authorizeProfileChange(p)) return;
    if (!mounted) return;
    final res = await showDialog<_ProfileForm>(
      context: context,
      builder: (_) => _ProfileEditorDialog(existing: p),
    );
    if (res == null) return;
    await UD.updateProfile(
      p.copyWith(
        name: res.name,
        avatar: res.avatar,
        isKid: res.isKid,
        pin: res.clearPin ? null : res.pin,
        clearPin: res.clearPin,
      ),
    );
    await _load();
  }

  Future<void> _delete(Profile p) async {
    if (!await _authorizeProfileChange(p)) return;
    if (!mounted) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('${S.t('delete_profile')}: ${p.name}'),
        content: Text(S.t('delete_confirm')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(S.t('cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(S.t('yes')),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await UD.deleteProfile(p.id);
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.pickerMode ? S.t('switch_profile') : S.t('profiles')),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : GridView.builder(
              padding: const EdgeInsets.all(20),
              gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: 170,
                childAspectRatio: 0.85,
                crossAxisSpacing: 16,
                mainAxisSpacing: 20,
              ),
              itemCount: _profiles.length + 1,
              itemBuilder: (context, i) {
                if (i == _profiles.length) {
                  return _AddTile(onTap: _create);
                }
                final p = _profiles[i];
                final isActive = UD.activeProfile.value == p.id;
                return _ProfileTile(
                  profile: p,
                  isActive: isActive,
                  pickerMode: widget.pickerMode,
                  onTap: () => _pick(p),
                  onEdit: () => _edit(p),
                  onDelete: () => _delete(p),
                );
              },
            ),
    );
  }
}

class _AddTile extends StatelessWidget {
  final VoidCallback onTap;
  const _AddTile({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 92,
            height: 92,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white24, width: 2),
            ),
            child: const Icon(Icons.add, size: 42, color: Colors.white70),
          ),
          const SizedBox(height: 10),
          Text(
            S.t('add_profile'),
            style: const TextStyle(fontSize: 13, color: Colors.white70),
          ),
        ],
      ),
    );
  }
}

class _ProfileTile extends StatelessWidget {
  final Profile profile;
  final bool isActive;
  final bool pickerMode;
  final VoidCallback onTap;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _ProfileTile({
    required this.profile,
    required this.isActive,
    required this.pickerMode,
    required this.onTap,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      onLongPress: pickerMode ? null : onEdit,
      borderRadius: BorderRadius.circular(12),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Stack(
            children: [
              Container(
                width: 92,
                height: 92,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: isActive
                      ? const Color(0xFFE50914).withOpacity(0.25)
                      : Colors.white10,
                  border: Border.all(
                    color: isActive ? const Color(0xFFE50914) : Colors.white12,
                    width: 3,
                  ),
                ),
                alignment: Alignment.center,
                child: Text(profile.avatar, style: const TextStyle(fontSize: 40)),
              ),
              if (profile.pin != null)
                Positioned(
                  right: 0,
                  bottom: 0,
                  child: Container(
                    padding: const EdgeInsets.all(3),
                    decoration: const BoxDecoration(
                      color: Colors.black87,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.lock, size: 14, color: Colors.white70),
                  ),
                ),
              if (profile.isKid)
                Positioned(
                  left: 0,
                  bottom: 0,
                  child: Container(
                    padding: const EdgeInsets.all(3),
                    decoration: const BoxDecoration(
                      color: Colors.black87,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.child_care, size: 14, color: Colors.white70),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            profile.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 14,
              fontWeight: isActive ? FontWeight.w800 : FontWeight.w600,
              color: isActive ? const Color(0xFFE50914) : Colors.white,
            ),
          ),
          if (!pickerMode)
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                IconButton(
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.edit, size: 16, color: Colors.white54),
                  onPressed: onEdit,
                ),
                IconButton(
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.delete_outline, size: 16, color: Colors.white38),
                  onPressed: profile.id == UD.defaultId ? null : onDelete,
                ),
              ],
            ),
        ],
      ),
    );
  }
}

class _ProfileForm {
  final String name;
  final String avatar;
  final bool isKid;
  final String? pin;
  final bool clearPin;
  const _ProfileForm({
    required this.name,
    required this.avatar,
    required this.isKid,
    required this.pin,
    this.clearPin = false,
  });
}

class _ProfileEditorDialog extends StatefulWidget {
  final Profile? existing;
  const _ProfileEditorDialog({this.existing});

  @override
  State<_ProfileEditorDialog> createState() => _ProfileEditorDialogState();
}

class _ProfileEditorDialogState extends State<_ProfileEditorDialog> {
  late final TextEditingController _name =
      TextEditingController(text: widget.existing?.name ?? '');
  late String _avatar = widget.existing?.avatar ?? '🙂';
  late bool _isKid = widget.existing?.isKid ?? false;
  late final TextEditingController _pin = TextEditingController();
  bool _clearExistingPin = false;

  static const List<String> _avatars = [
    '👤', '😎', '🦊', '🐼', '🐯', '🦁', '🐨', '🐵',
    '🚀', '⚽', '🎬', '🎮', '🍿', '🌟', '🔥', '💎',
    '👽', '🤖', '🎵', '🏀', '🧠', '☕', '🌙', '🛸',
  ];

  @override
  void dispose() {
    _name.dispose();
    _pin.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(
        widget.existing == null ? S.t('create_profile') : S.t('profile_name'),
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Text(_avatar, style: const TextStyle(fontSize: 52)),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _name,
              decoration: InputDecoration(
                labelText: S.t('profile_name'),
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              S.t('choose_avatar'),
              style: const TextStyle(fontSize: 12, color: Colors.white54),
            ),
            const SizedBox(height: 6),
            SizedBox(
              height: 130,
              child: GridView.count(
                crossAxisCount: 6,
                mainAxisSpacing: 6,
                crossAxisSpacing: 6,
                children: [
                  for (final a in _avatars)
                    InkWell(
                      onTap: () => setState(() => _avatar = a),
                      borderRadius: BorderRadius.circular(6),
                      child: Container(
                        decoration: BoxDecoration(
                          color: _avatar == a
                              ? const Color(0xFFE50914).withOpacity(0.3)
                              : Colors.white10,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        alignment: Alignment.center,
                        child: Text(a, style: const TextStyle(fontSize: 22)),
                      ),
                    ),
                ],
              ),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _isKid,
              onChanged: (v) => setState(() => _isKid = v),
              title: Text(S.t('kids_mode')),
            ),
            if (widget.existing?.pin != null) ...[
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                value: _clearExistingPin,
                onChanged: (v) => setState(() => _clearExistingPin = v ?? false),
                title: const Text('إزالة رمز PIN الحالي'),
                subtitle: const Text('لن يُحذف الرمز إلا إذا فعّلت هذا الخيار صراحةً.'),
                controlAffinity: ListTileControlAffinity.leading,
              ),
            ],
            TextField(
              controller: _pin,
              keyboardType: TextInputType.number,
              maxLength: 4,
              obscureText: true,
              decoration: InputDecoration(
                labelText: '${S.t('pin')} (${S.t('no_pin')})',
                border: const OutlineInputBorder(),
                counterText: '',
              ),
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(S.t('cancel')),
        ),
        FilledButton(
          onPressed: () {
            final pinText = _pin.text.trim();
            Navigator.pop(
              context,
              _ProfileForm(
                name: _name.text.trim(),
                avatar: _avatar,
                isKid: _isKid,
                pin: pinText.length == 4 ? pinText : null,
                clearPin: _clearExistingPin,
              ),
            );
          },
          child: Text(S.t('save')),
        ),
      ],
    );
  }
}

/// حوار الرمز السري (PIN) — أرقام فقط.
Future<bool?> showPinDialog(BuildContext context, {String? expected}) async {
  return showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _PinDialog(expected: expected),
  );
}

class _PinDialog extends StatefulWidget {
  final String? expected;
  const _PinDialog({this.expected});

  @override
  State<_PinDialog> createState() => _PinDialogState();
}

class _PinDialogState extends State<_PinDialog> {
  String _pin = '';
  bool _error = false;

  void _add(String d) {
    if (_pin.length >= 4) return;
    setState(() {
      _pin += d;
      _error = false;
    });
    if (_pin.length == 4) _check();
  }

  void _back() {
    if (_pin.isEmpty) return;
    setState(() {
      _pin = _pin.substring(0, _pin.length - 1);
      _error = false;
    });
  }

  void _check() {
    final expected = widget.expected;
    if (expected == null) {
      Navigator.pop(context, true);
      return;
    }
    if (expected == _pin) {
      Navigator.pop(context, true);
    } else {
      setState(() {
        _error = true;
        _pin = '';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(S.t('enter_pin')),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              for (var i = 0; i < 4; i++)
                Container(
                  width: 16,
                  height: 16,
                  margin: const EdgeInsets.symmetric(horizontal: 6),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: i < _pin.length
                        ? (_error ? Colors.red : const Color(0xFFE50914))
                        : Colors.white24,
                  ),
                ),
            ],
          ),
          if (_error) ...[
            const SizedBox(height: 10),
            Text(
              S.t('wrong_pin'),
              style: const TextStyle(color: Colors.redAccent, fontSize: 12),
            ),
          ],
          const SizedBox(height: 14),
          SizedBox(
            width: 240,
            child: GridView.count(
              shrinkWrap: true,
              crossAxisCount: 3,
              mainAxisSpacing: 8,
              crossAxisSpacing: 8,
              childAspectRatio: 1.7,
              children: [
                for (var i = 1; i <= 9; i++)
                  _key('$i'),
                _key('⌫', onTap: _back),
                _key('0'),
                _key('✓', onTap: _check),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _key(String label, {VoidCallback? onTap}) {
    return InkWell(
      onTap: onTap ?? () => _add(label),
      borderRadius: BorderRadius.circular(8),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white10,
          borderRadius: BorderRadius.circular(8),
        ),
        alignment: Alignment.center,
        child: Text(
          label,
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
        ),
      ),
    );
  }
}
