import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show Supabase, UserAttributes;

import 'package:supra_mobile_ui/models/notification_preference.dart';
import 'package:supra_mobile_ui/services/supra_api_service.dart';

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
  }

  Future<void> _logout() async {
    try {
      await SupraService.instance.logout();
      if (!mounted) return;
      Navigator.of(context).popUntil((route) => route.isFirst);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Could not sign out: $error')));
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
        const SnackBar(content: Text('Profile picture updated successfully')),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to upload profile picture: $error')),
      );
    } finally {
      if (mounted) setState(() => _uploadingAvatar = false);
    }
  }

  Future<void> _showEditProfileDialog() async {
    final currentName = SupraService.instance.currentUser?.fullName ?? '';
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
                'Edit Profile',
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
                    labelText: 'Full Name',
                    hintText: 'Enter your full name',
                  ),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'Full name is required';
                    }
                    if (value.trim().length > 255) {
                      return 'Full name must be at most 255 characters';
                    }
                    return null;
                  },
                ),
              ),
              actions: [
                TextButton(
                  onPressed:
                      submitting ? null : () => Navigator.of(dialogContext).pop(),
                  child: const Text('Cancel'),
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
                              Navigator.of(dialogContext).pop(updated.fullName);
                            }
                          } catch (error) {
                            setDialogState(() => submitting = false);
                            if (dialogContext.mounted) {
                              ScaffoldMessenger.of(dialogContext).showSnackBar(
                                SnackBar(
                                  content:
                                      Text('Failed to update profile: $error'),
                                ),
                              );
                            }
                          }
                        },
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Text(submitting ? 'Saving...' : 'Save'),
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
        const SnackBar(content: Text('Profile updated successfully')),
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
    String? currentPasswordError;

    final changed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        final theme = Theme.of(dialogContext);
        final colorScheme = theme.colorScheme;
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: Text(
                'Change Password',
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
                      onChanged: (_) {
                        if (currentPasswordError != null) {
                          setDialogState(() => currentPasswordError = null);
                        }
                      },
                      decoration: InputDecoration(
                        labelText: 'Current Password',
                        hintText: 'Enter your current password',
                        errorText: currentPasswordError,
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
                          return 'Please enter your current password';
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
                        labelText: 'New Password',
                        hintText: 'Minimum 6 characters',
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
                          return 'Please enter a new password';
                        }
                        if (value.length < 6) {
                          return 'Password must be at least 6 characters';
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
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: submitting
                      ? null
                      : () async {
                          setDialogState(() => currentPasswordError = null);
                          if (!formKey.currentState!.validate()) return;
                          setDialogState(() => submitting = true);

                          final userEmail =
                              SupraService.instance.currentUser?.email ??
                                  Supabase.instance.client.auth.currentUser
                                      ?.email ??
                                  '';

                          try {
                            await Supabase.instance.client.auth
                                .signInWithPassword(
                              email: userEmail,
                              password: currentPasswordController.text,
                            );
                          } catch (_) {
                            setDialogState(() {
                              submitting = false;
                              currentPasswordError =
                                  'Current password incorrect';
                            });
                            if (dialogContext.mounted) {
                              ScaffoldMessenger.of(dialogContext).showSnackBar(
                                const SnackBar(
                                  content: Text('Current password incorrect'),
                                ),
                              );
                            }
                            return;
                          }

                          try {
                            await Supabase.instance.client.auth.updateUser(
                              UserAttributes(
                                password: newPasswordController.text,
                              ),
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
                                      'Failed to change password: $error'),
                                ),
                              );
                            }
                          }
                        },
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Text(submitting ? 'Updating...' : 'Update'),
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
        const SnackBar(content: Text('Password updated successfully')),
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
                'Delete Account',
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: colorScheme.error,
                ),
              ),
              content: Text(
                'Are you sure? This action is irreversible.',
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
                  child: const Text('Cancel'),
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
                                  content:
                                      Text('Failed to delete account: $error'),
                                ),
                              );
                            }
                          }
                        },
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Text(deleting ? 'Deleting...' : 'Delete'),
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

    final cardShape = theme.cardTheme.shape ??
        RoundedRectangleBorder(borderRadius: BorderRadius.circular(16));
    final cardColor = theme.cardTheme.color ?? colorScheme.surface;
    final cardElevation = theme.cardTheme.elevation ?? 0;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Text(
            'Settings',
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
                  'Profile',
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
                                backgroundColor:
                                    colorScheme.primary.withValues(alpha: 0.15),
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
                                            style:
                                                textTheme.titleLarge?.copyWith(
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
                                      user?.fullName ?? 'User',
                                      style: textTheme.titleMedium?.copyWith(
                                        fontWeight: FontWeight.w700,
                                        color: colorScheme.onSurface,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      user?.email ?? '',
                                      style: textTheme.bodySmall?.copyWith(
                                        color: colorScheme.onSurfaceVariant,
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
                  'Account',
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
                    'Edit Profile',
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
                  leading: Icon(
                    Icons.lock_outline,
                    color: colorScheme.primary,
                  ),
                  title: Text(
                    'Change Password',
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
                Divider(
                  height: 1,
                  color: colorScheme.outlineVariant.withValues(alpha: 0.5),
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(
                    Icons.delete_outline,
                    color: colorScheme.error,
                  ),
                  title: Text(
                    'Delete Account',
                    style: textTheme.bodyLarge?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: colorScheme.error,
                    ),
                  ),
                  trailing: Icon(
                    Icons.chevron_right,
                    color: colorScheme.error,
                  ),
                  onTap: _showDeleteAccountDialog,
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 20),
        // 3. Notification preferences header + "Coming Soon" badge.
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Row(
            children: [
              Text(
                'Alert preferences',
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
                  'Coming Soon',
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
                    'Unhealthy AQI alerts',
                    style: textTheme.bodyLarge?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: colorScheme.onSurface,
                    ),
                  ),
                  subtitle: Text(
                    'Notify when AQI reaches unhealthy levels',
                    style: textTheme.bodySmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                  value: _prefs.alertUnhealthyAqi,
                  onChanged:
                      _saving ? null : (v) => _update(alertUnhealthyAqi: v),
                ),
                Divider(
                  height: 1,
                  indent: 16,
                  endIndent: 16,
                  color: colorScheme.outlineVariant.withValues(alpha: 0.5),
                ),
                SwitchListTile(
                  title: Text(
                    'Heavy rain alerts',
                    style: textTheme.bodyLarge?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: colorScheme.onSurface,
                    ),
                  ),
                  subtitle: Text(
                    'Notify when rain probability is high on your route',
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
                    'Severe traffic alerts',
                    style: textTheme.bodyLarge?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: colorScheme.onSurface,
                    ),
                  ),
                  subtitle: Text(
                    'Notify when traffic density hits heavy levels',
                    style: textTheme.bodySmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                  value: _prefs.alertSevereTraffic,
                  onChanged:
                      _saving ? null : (v) => _update(alertSevereTraffic: v),
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
              'Sign out',
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
  }) async {
    final next = _prefs.copyWith(
      alertUnhealthyAqi: alertUnhealthyAqi,
      alertHeavyRain: alertHeavyRain,
      alertSevereTraffic: alertSevereTraffic,
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
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$error')));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
}
