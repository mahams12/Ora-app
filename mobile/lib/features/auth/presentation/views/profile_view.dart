import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';

import '../../../../app/di/providers.dart';
import '../../../../app/theme/ora_colors.dart';
import '../../../../app/theme/ora_spacing.dart';
import '../../../../app/theme/ora_typography.dart';
import '../../../../app/theme/widgets/widgets.dart';
import '../../../auth/presentation/view_models/session_user_profile.dart';

/// Profile editor — display name + photo. Photo is stored server-side as a
/// capped base64 data URL on the user document.
class ProfileView extends ConsumerStatefulWidget {
  const ProfileView({super.key});

  @override
  ConsumerState<ProfileView> createState() => _ProfileViewState();
}

class _ProfileViewState extends ConsumerState<ProfileView> {
  final _nameController = TextEditingController();
  final _picker = ImagePicker();
  String? _avatarData;
  bool _avatarChanged = false;
  bool _avatarCleared = false;
  bool _saving = false;
  String? _error;
  bool _seeded = false;

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  void _seed() {
    if (_seeded) return;
    _seeded = true;
    final profile = ref.read(sessionUserProfileProvider);
    _nameController.text = profile?.displayName?.trim() ?? '';
    _avatarData = profile?.avatarData;
  }

  String _initials(String? name) {
    final parts = (name ?? '')
        .trim()
        .split(RegExp(r'\s+'))
        .where((p) => p.isNotEmpty)
        .toList();
    if (parts.isEmpty) return 'O';
    return parts
        .take(2)
        .map((p) => p[0].toUpperCase())
        .join();
  }

  Future<void> _pickPhoto() async {
    try {
      final picked = await _picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 1024,
        maxHeight: 1024,
        imageQuality: 90,
      );
      if (picked == null) return;
      final bytes = await picked.readAsBytes();
      final decoded = img.decodeImage(bytes);
      if (decoded == null) {
        setState(() => _error = 'Could not read that image.');
        return;
      }
      final resized = img.copyResize(
        decoded,
        width: 512,
        height: 512,
        interpolation: img.Interpolation.average,
      );
      final jpeg = img.encodeJpg(resized, quality: 82);
      setState(() {
        _avatarData = 'data:image/jpeg;base64,${base64Encode(jpeg)}';
        _avatarChanged = true;
        _avatarCleared = false;
        _error = null;
      });
    } catch (_) {
      setState(() => _error = 'Could not open the photo picker.');
    }
  }

  Future<void> _save() async {
    final name = _nameController.text.trim();
    if (name.length < 2) {
      setState(() => _error = 'Name must be at least 2 characters.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final profile = await ref.read(updateProfileUseCaseProvider)(
        displayName: name,
        avatarData: _avatarChanged && !_avatarCleared ? _avatarData : null,
        clearAvatar: _avatarCleared,
      );
      ref.read(sessionUserProfileProvider.notifier).setProfile(profile);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Profile updated')),
      );
      await Navigator.of(context).maybePop();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = ref.read(failureMapperProvider).fromException(error).userMessage;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    _seed();
    final profile = ref.watch(sessionUserProfileProvider);
    final name = _nameController.text.trim();

    return Scaffold(
      backgroundColor: OraColors.background,
      appBar: AppBar(
        backgroundColor: OraColors.background,
        foregroundColor: OraColors.textPrimary,
        title: Text(
          'Profile',
          style: OraTypography.title(OraColors.textPrimary),
        ),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(OraSpacing.lg),
          children: [
            Center(
              child: Column(
                children: [
                  OraAvatar(
                    initials: _initials(name.isEmpty ? profile?.displayName : name),
                    avatarData: _avatarData,
                    size: 96,
                    fontSize: 34,
                  ),
                  const SizedBox(height: OraSpacing.sm),
                  TextButton.icon(
                    onPressed: _pickPhoto,
                    icon: const Icon(Icons.photo_camera_outlined, size: 18),
                    label: Text(
                      _avatarData == null ? 'Add photo' : 'Change photo',
                      style: OraTypography.label(OraColors.primary),
                    ),
                  ),
                  if (_avatarData != null)
                    TextButton(
                      onPressed: () => setState(() {
                        _avatarData = null;
                        _avatarChanged = true;
                        _avatarCleared = true;
                      }),
                      child: Text(
                        'Remove photo',
                        style: OraTypography.caption(OraColors.danger),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: OraSpacing.lg),
            OraTextField(
              controller: _nameController,
              label: 'Name',
              hint: 'Your name',
              textCapitalization: TextCapitalization.words,
              onChanged: (_) => setState(() {}),
            ),
            if (_error != null) ...[
              const SizedBox(height: OraSpacing.sm),
              Text(
                _error!,
                style: OraTypography.caption(OraColors.danger),
              ),
            ],
            const SizedBox(height: OraSpacing.xl),
            OraButton(
              label: 'Save',
              isLoading: _saving,
              onPressed: _saving ? null : _save,
            ),
          ],
        ),
      ),
    );
  }
}
