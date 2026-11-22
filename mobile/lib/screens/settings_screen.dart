import '../utils/display_text.dart';

import 'package:flutter/material.dart';

import '../models/user.dart';
import '../widgets/news_severity_selector.dart';

import 'package:image_picker/image_picker.dart';

import 'package:supra_mobile_ui/models/notification_preference.dart';
import 'package:supra_mobile_ui/services/supra_api_service.dart';

import 'commutes_screen.dart';

/// Settings: profile + notification preferences (ERD entity
/// NOTIFICATION_PREFERENCE) that drive Agent 2 alert rules.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late NotificationPreference _prefs;
  bool _saving = false;
  bool _uploadingAvatar = false;

  @override
  void initState() {
    super.initState();
    _prefs = SupraService.instance.preferences;
    SupraService.instance.addListener(_syncPreferences);
  }

  void _syncPreferences() {
    if (mounted && !_saving) {
      setState(() => _prefs = SupraService.instance.preferences);
    }
  }

  @override
  void dispose() {
    SupraService.instance.removeListener(_syncPreferences);
    super.dispose();
  }

  Future<void> _logout() async {
    try {
      await SupraService.instance.logout();
      if (!mounted) return;
      Navigator.of(context).popUntil((route) => route.isFirst);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Logout gagal: ${displayError(error)}')),
      );
    }
  }

  Future<void> _pickAndUploadAvatar() async {
    if (_uploadingAvatar) return;
    try {
      final picker = ImagePicker();
      final pickedFile = await picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 512,
        maxHeight: 512,
        imageQuality: 85,
      );
      if (pickedFile == null) return;

      setState(() => _uploadingAvatar = true);
      final bytes = await pickedFile.readAsBytes();
      await SupraService.instance.uploadAvatar(bytes, pickedFile.name);
      if (!mounted) return;
      setState(() {});
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Foto profil berhasil diperbarui')),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Foto profil gagal diunggah: ${displayError(error)}'),
        ),
      );
    } finally {
      if (mounted) setState(() => _uploadingAvatar = false);
    }
  }

  Future<void> _showEditProfileDialog() async {
    final currentName = SupraService.instance.currentUser?.username ?? '';
    final controller = TextEditingController(text: currentName);
    final formKey = GlobalKey<FormState>();
    bool submitting = false;

    final updatedName = await showDialog<String>(
      context: context,
      builder: (dialogContext) {
        final theme = Theme.of(dialogContext);
        final colorScheme = theme.colorScheme;
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: Text(
                'Ubah profil',
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: colorScheme.onSurface,
                ),
              ),
              content: Form(
                key: formKey,
                child: TextFormField(
                  controller: controller,
                  autofocus: true,
                  enabled: !submitting,
                  decoration: const InputDecoration(
                    labelText: 'Username',
                    hintText: 'Masukkan username Anda',
                  ),
                  validator: (value) => User.isValidUsername(value ?? '')
                      ? null
                      : User.usernameHint,
                ),
              ),
              actions: [
                TextButton(
                  onPressed: submitting
                      ? null
                      : () => Navigator.of(dialogContext).pop(),
                  child: const Text('Batal'),
                ),
                ElevatedButton(
                  onPressed: submitting
                      ? null
                      : () async {
                          if (!formKey.currentState!.validate()) return;
                          setDialogState(() => submitting = true);
                          try {
                            final updated = await SupraService.instance
                                .updateProfile(controller.text.trim());
                            if (dialogContext.mounted) {
                              Navigator.of(dialogContext).pop(updated.username);
                            }
                          } catch (error) {
                            setDialogState(() => submitting = false);
                            if (dialogContext.mounted) {
                              ScaffoldMessenger.of(dialogContext).showSnackBar(
                                SnackBar(
                                  content: Text(
                                    'Profil gagal diperbarui: ${displayError(error)}',
                                  ),
                                ),
                              );
                            }
                          }
                        },
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Text(submitting ? 'Menyimpan…' : 'Simpan'),
                  ),
                ),
              ],
            );
          },
        );
      },
    );

    controller.dispose();
    if (updatedName != null && mounted) {
      setState(() {});
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Profil berhasil diperbarui')),
      );
    }
  }

  Future<void> _showChangePasswordDialog() async {
    final currentPasswordController = TextEditingController();
    final newPasswordController = TextEditingController();
    final formKey = GlobalKey<FormState>();
    bool submitting = false;
    bool obscureCurrent = true;
    bool obscureNew = true;

    final changed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        final theme = Theme.of(dialogContext);
        final colorScheme = theme.colorScheme;
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: Text(
                'Ubah password',
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: colorScheme.onSurface,
                ),
              ),
              content: Form(
                key: formKey,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextFormField(
                      controller: currentPasswordController,
                      autofocus: true,
                      obscureText: obscureCurrent,
                      enabled: !submitting,
                      decoration: InputDecoration(
                        labelText: 'Password saat ini',
                        hintText: 'Masukkan password saat ini',
                        suffixIcon: IconButton(
                          icon: Icon(
                            obscureCurrent
                                ? Icons.visibility_off
                                : Icons.visibility,
                          ),
                          onPressed: () => setDialogState(
                            () => obscureCurrent = !obscureCurrent,
                          ),
                        ),
                      ),
                      validator: (value) {
                        if (value == null || value.isEmpty) {
                          return 'Masukkan password saat ini';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 14),
                    TextFormField(
                      controller: newPasswordController,
                      obscureText: obscureNew,
                      enabled: !submitting,
                      decoration: InputDecoration(
                        labelText: 'Password baru',
                        hintText: 'Minimal 6 karakter',
                        suffixIcon: IconButton(
                          icon: Icon(
                            obscureNew
                                ? Icons.visibility_off
                                : Icons.visibility,
                          ),
                          onPressed: () =>
                              setDialogState(() => obscureNew = !obscureNew),
                        ),
                      ),
                      validator: (value) {
                        if (value == null || value.isEmpty) {
                          return 'Masukkan password baru';
                        }
                        if (value.length < 6) {
                          return 'Password harus terdiri dari minimal 6 karakter';
                        }
                        return null;
                      },
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: submitting
                      ? null
                      : () => Navigator.of(dialogContext).pop(false),
                  child: const Text('Batal'),
                ),
                ElevatedButton(
                  onPressed: submitting
                      ? null
                      : () async {
                          if (!formKey.currentState!.validate()) return;
                          setDialogState(() => submitting = true);

                          try {
                            await SupraService.instance.changePassword(
                              currentPasswordController.text,
                              newPasswordController.text,
                            );
                            if (dialogContext.mounted) {
                              Navigator.of(dialogContext).pop(true);
                            }
                          } catch (error) {
                            setDialogState(() => submitting = false);
                            if (dialogContext.mounted) {
                              ScaffoldMessenger.of(dialogContext).showSnackBar(
                                SnackBar(
                                  content: Text(
                                    'Password gagal diubah: ${displayError(error)}',
                                  ),
                                ),
                              );
                            }
                          }
                        },
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Text(submitting ? 'Memperbarui…' : 'Perbarui'),
                  ),
                ),
              ],
            );
          },
        );
      },
    );

    currentPasswordController.dispose();
    newPasswordController.dispose();
    if (changed == true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Password berhasil diperbarui')),
      );
    }
  }

  Future<void> _showDeleteAccountDialog() async {
    bool deleting = false;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        final theme = Theme.of(dialogContext);
        final colorScheme = theme.colorScheme;
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: Text(
                'Hapus akun',
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: colorScheme.error,
                ),
              ),
              content: Text(
                'Yakin ingin menghapus akun? Tindakan ini tidak dapat dibatalkan.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: colorScheme.error,
                  fontWeight: FontWeight.w600,
                ),
              ),
              actions: [
                TextButton(
                  onPressed: deleting
                      ? null
                      : () => Navigator.of(dialogContext).pop(false),
                  child: const Text('Batal'),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: colorScheme.error,
                    foregroundColor: colorScheme.onError,
                  ),
                  onPressed: deleting
                      ? null
                      : () async {
                          setDialogState(() => deleting = true);
                          try {
                            await SupraService.instance.deleteAccount();
                            if (dialogContext.mounted) {
                              Navigator.of(dialogContext).pop(true);
                            }
                          } catch (error) {
                            setDialogState(() => deleting = false);
                            if (dialogContext.mounted) {
                              ScaffoldMessenger.of(dialogContext).showSnackBar(
                                SnackBar(
                                  content: Text(
                                    'Akun gagal dihapus: ${displayError(error)}',
                                  ),
                                ),
                              );
                            }
                          }
                        },
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Text(deleting ? 'Menghapus…' : 'Hapus'),
                  ),
                ),
              ],
            );
          },
        );
      },
    );

    if (confirmed == true && mounted) {
      Navigator.of(context).popUntil((route) => route.isFirst);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final textTheme = theme.textTheme;
    final user = SupraService.instance.currentUser;
    final hasAvatar = user?.avatarUrl != null && user!.avatarUrl!.isNotEmpty;

    final cardShape =
        theme.cardTheme.shape ??
        RoundedRectangleBorder(borderRadius: BorderRadius.circular(16));
    final cardColor = theme.cardTheme.color ?? colorScheme.surface;
    final cardElevation = theme.cardTheme.elevation ?? 0;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Text(
            'Pengaturan',
            style: textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w800,
              color: colorScheme.onSurface,
            ),
          ),
        ),
        const SizedBox(height: 24),
        // 1. Profile card.
        Card(
          margin: const EdgeInsets.symmetric(horizontal: 4),
          elevation: cardElevation,
          color: cardColor,
          shape: cardShape,
          clipBehavior: Clip.antiAlias,
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Profil',
                  style: textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: colorScheme.onSurface,
                  ),
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    // 1. Dedicated Avatar Hitbox (triggers photo picker).
                    GestureDetector(
                      onTap: _uploadingAvatar ? null : _pickAndUploadAvatar,
                      behavior: HitTestBehavior.opaque,
                      child: MouseRegion(
                        cursor: _uploadingAvatar
                            ? SystemMouseCursors.basic
                            : SystemMouseCursors.click,
                        child: Padding(
                          padding: const EdgeInsets.only(right: 4, bottom: 4),
                          child: Stack(
                            clipBehavior: Clip.none,
                            children: [
                              CircleAvatar(
                                radius: 30,
                                backgroundColor: colorScheme.primary.withValues(
                                  alpha: 0.15,
                                ),
                                backgroundImage: hasAvatar
                                    ? NetworkImage(user.avatarUrl!)
                                    : null,
                                child: _uploadingAvatar
                                    ? SizedBox(
                                        width: 24,
                                        height: 24,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2.5,
                                          color: colorScheme.primary,
                                        ),
                                      )
                                    : !hasAvatar
                                    ? Text(
                                        user?.initials ?? '?',
                                        style: textTheme.titleLarge?.copyWith(
                                          color: colorScheme.primary,
                                          fontWeight: FontWeight.w800,
                                        ),
                                      )
                                    : null,
                              ),
                              Positioned(
                                bottom: -4,
                                right: -4,
                                child: Container(
                                  padding: const EdgeInsets.all(6),
                                  decoration: BoxDecoration(
                                    color: colorScheme.primary,
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                      color: cardColor,
                                      width: 2,
                                    ),
                                  ),
                                  child: Icon(
                                    Icons.camera_alt,
                                    size: 15,
                                    color: colorScheme.onPrimary,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    // 2. Dedicated Text & Chevron Hitbox (triggers Edit Profile dialog).
                    Expanded(
                      child: InkWell(
                        onTap: _showEditProfileDialog,
                        borderRadius: BorderRadius.circular(12),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            vertical: 8,
                            horizontal: 8,
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      (user?.username.isNotEmpty ?? false)
                                          ? user!.username
                                          : 'Pengguna',
                                      style: textTheme.titleMedium?.copyWith(
                                        fontWeight: FontWeight.w700,
                                        color: colorScheme.onSurface,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              Icon(
                                Icons.chevron_right,
                                color: colorScheme.onSurfaceVariant,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 20),
        // 2. Account Management card (immediately below Profile card).
        Card(
          margin: const EdgeInsets.symmetric(horizontal: 4),
          elevation: cardElevation,
          color: cardColor,
          shape: cardShape,
          clipBehavior: Clip.antiAlias,
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Akun',
                  style: textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: colorScheme.onSurface,
                  ),
                ),
                const SizedBox(height: 8),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(
                    Icons.edit_outlined,
                    color: colorScheme.primary,
                  ),
                  title: Text(
                    'Ubah profil',
                    style: textTheme.bodyLarge?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: colorScheme.onSurface,
                    ),
                  ),
                  trailing: Icon(
                    Icons.chevron_right,
                    color: colorScheme.onSurfaceVariant,
                  ),
                  onTap: _showEditProfileDialog,
                ),
                Divider(
                  height: 1,
                  color: colorScheme.outlineVariant.withValues(alpha: 0.5),
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.lock_outline, color: colorScheme.primary),
                  title: Text(
                    'Ubah password',
                    style: textTheme.bodyLarge?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: colorScheme.onSurface,
                    ),
                  ),
                  trailing: Icon(
                    Icons.chevron_right,
                    color: colorScheme.onSurfaceVariant,
                  ),
                  onTap: _showChangePasswordDialog,
                ),
                ListTile(
                  leading: Icon(
                    Icons.bookmarks_outlined,
                    color: colorScheme.primary,
                  ),
                  title: const Text('Tempat dan rutinitas tersimpan'),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const CommutesScreen(),
                    ),
                  ),
                ),
                Divider(
                  height: 1,
                  color: colorScheme.outlineVariant.withValues(alpha: 0.5),
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.delete_outline, color: colorScheme.error),
                  title: Text(
                    'Hapus akun',
                    style: textTheme.bodyLarge?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: colorScheme.error,
                    ),
                  ),
                  trailing: Icon(Icons.chevron_right, color: colorScheme.error),
                  onTap: _showDeleteAccountDialog,
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 20),
        // 3. Active account-scoped notification preferences.
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Row(
            children: [
              Text(
                'Preferensi peringatan',
                style: textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: colorScheme.onSurface,
                ),
              ),
              const SizedBox(width: 10),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: colorScheme.primary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  _saving ? 'Menyimpan…' : 'Tersimpan otomatis',
                  style: textTheme.labelSmall?.copyWith(
                    color: colorScheme.primary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        // Notification preferences card replicating Profile card styling.
        Card(
          margin: const EdgeInsets.symmetric(horizontal: 4),
          elevation: cardElevation,
          color: cardColor,
          shape: cardShape,
          clipBehavior: Clip.antiAlias,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Column(
              children: [
                SwitchListTile(
                  title: Text(
                    'Peringatan AQI tidak sehat',
                    style: textTheme.bodyLarge?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: colorScheme.onSurface,
                    ),
                  ),
                  subtitle: Text(
                    'Beri tahu saat AQI mencapai tingkat tidak sehat',
                    style: textTheme.bodySmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                  value: _prefs.alertUnhealthyAqi,
                  onChanged: _saving
                      ? null
                      : (v) => _update(alertUnhealthyAqi: v),
                ),
                Divider(
                  height: 1,
                  indent: 16,
                  endIndent: 16,
                  color: colorScheme.outlineVariant.withValues(alpha: 0.5),
                ),
                SwitchListTile(
                  title: Text(
                    'Peringatan hujan lebat',
                    style: textTheme.bodyLarge?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: colorScheme.onSurface,
                    ),
                  ),
                  subtitle: Text(
                    'Beri tahu saat peluang hujan tinggi di rute Anda',
                    style: textTheme.bodySmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                  value: _prefs.alertHeavyRain,
                  onChanged: _saving ? null : (v) => _update(alertHeavyRain: v),
                ),
                Divider(
                  height: 1,
                  indent: 16,
                  endIndent: 16,
                  color: colorScheme.outlineVariant.withValues(alpha: 0.5),
                ),
                SwitchListTile(
                  title: Text(
                    'Peringatan kemacetan parah',
                    style: textTheme.bodyLarge?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: colorScheme.onSurface,
                    ),
                  ),
                  subtitle: Text(
                    'Beri tahu saat lalu lintas mengalami kemacetan parah',
                    style: textTheme.bodySmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                  value: _prefs.alertSevereTraffic,
                  onChanged: _saving
                      ? null
                      : (v) => _update(alertSevereTraffic: v),
                ),
                SwitchListTile(
                  title: const Text('Berita relevan'),
                  subtitle: const Text(
                    'Berita yang sesuai dengan perjalanan atau wilayah Anda.',
                  ),
                  value: _prefs.alertRelevantNews,
                  onChanged: _saving
                      ? null
                      : (v) => _update(alertRelevantNews: v),
                ),
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: NewsSeveritySelector(
                    value: _prefs.newsMinSeverity,
                    onChanged: _saving || !_prefs.alertRelevantNews
                        ? null
                        : (v) => _update(newsMinSeverity: v),
                  ),
                ),
                const Padding(
                  padding: EdgeInsets.fromLTRB(16, 0, 16, 16),
                  child: Text(
                    'Tingkat keparahan berita menggambarkan gangguan yang dilaporkan. Klasifikasi ini dibuat oleh aplikasi, bukan peringatan resmi terkini.',
                    style: TextStyle(fontSize: 12),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 30),
        // 4. Sign out button aligned horizontally with the cards above.
        Container(
          margin: const EdgeInsets.symmetric(horizontal: 4),
          width: double.infinity,
          child: ElevatedButton(
            onPressed: _logout,
            style: ElevatedButton.styleFrom(
              backgroundColor: colorScheme.errorContainer,
              foregroundColor: colorScheme.error,
              elevation: 0,
            ),
            child: Text(
              'Logout',
              style: textTheme.titleMedium?.copyWith(
                color: colorScheme.error,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _update({
    bool? alertUnhealthyAqi,
    bool? alertHeavyRain,
    bool? alertSevereTraffic,
    bool? alertRelevantNews,
    String? newsMinSeverity,
  }) async {
    final previous = _prefs;
    final next = _prefs.copyWith(
      alertUnhealthyAqi: alertUnhealthyAqi,
      alertHeavyRain: alertHeavyRain,
      alertSevereTraffic: alertSevereTraffic,
      alertRelevantNews: alertRelevantNews,
      newsMinSeverity: newsMinSeverity,
    );
    setState(() {
      _prefs = next;
      _saving = true;
    });
    try {
      await SupraService.instance.updatePreferences(next);
      if (mounted) setState(() => _prefs = SupraService.instance.preferences);
    } catch (error) {
      if (mounted) {
        setState(() => _prefs = previous);
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(displayError(error))));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
}
