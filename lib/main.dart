import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/services.dart';
import 'package:logger/logger.dart';
import 'dart:io';
import 'package:path/path.dart' as path;
import 'package:window_manager/window_manager.dart';

final logger = Logger(
  printer: PrettyPrinter(
    methodCount: 1,
    errorMethodCount: 5,
    lineLength: 50,
    colors: true,
    printEmojis: true,
    printTime: false,
  ),
  level: kReleaseMode ? Level.off : Level.debug,
);

const maxPreloadedImages = 11;

void main() async {
  logger.i('Application starting');
  WidgetsFlutterBinding.ensureInitialized();
  await windowManager.ensureInitialized();

  WindowOptions windowOptions = const WindowOptions(
      // size: Size(800, 600),
      center: true,
      backgroundColor: Colors.transparent,
      skipTaskbar: false,
      titleBarStyle: TitleBarStyle.normal,
      minimumSize: Size(500, 500));
  windowManager.waitUntilReadyToShow(windowOptions, () async {
    await windowManager.show();
    await windowManager.focus();
  });

  logger.i('Window initialized and shown');
  runApp(const ArtFaveApp());
}

class ArtFaveApp extends StatelessWidget {
  const ArtFaveApp({super.key});

  @override
  Widget build(BuildContext context) {
    logger.i('Building ArtFaveApp');
    return MaterialApp(
      title: 'ArtFave',
      theme: ThemeData(
        primarySwatch: Colors.blue,
      ),
      home: const HomePage(),
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  HomePageState createState() => HomePageState();
}

class HomePageState extends State<HomePage> {
  String? imageFolderPath;
  String? favoriteFolderPath;

  Future<void> pickFolder(bool isImageFolder) async {
    logger.i('Picking folder for ${isImageFolder ? 'images' : 'favorites'}');
    try {
      String? selectedDirectory = await FilePicker.platform.getDirectoryPath();
      if (selectedDirectory != null) {
        logger.i('Selected directory: $selectedDirectory');
        setState(() {
          if (isImageFolder) {
            imageFolderPath = selectedDirectory;
          } else {
            favoriteFolderPath = selectedDirectory;
          }
        });
      } else {
        logger.i('No directory selected');
      }
    } catch (e) {
      // エラーメッセージを表示
      if (mounted) {
        logger.e('Failed to pick folder: $e');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('エラー: フォルダの選択に失敗しました - $e')),
        );
      }
    }
  }

  void navigateToImageDisplayPage() {
    if (imageFolderPath != null &&
        favoriteFolderPath != null &&
        imageFolderPath != favoriteFolderPath) {
      logger.i('Navigating to ImageDisplayPage');
      logger.i('Image folder: $imageFolderPath');
      logger.i('Favorite folder: $favoriteFolderPath');
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => ImageDisplayPage(
            imageFolderPath: imageFolderPath!,
            favoriteFolderPath: favoriteFolderPath!,
          ),
        ),
      );
    } else {
      logger.w('Image folder and favorite folder are not set or are the same');
    }
  }

  @override
  Widget build(BuildContext context) {
    logger.d('Building HomePage');
    return Scaffold(
      appBar: AppBar(
        title: const Text('ArtFave'),
      ),
      body: Center(
        child: SingleChildScrollView(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _buildFolderSelector(
                icon: Icons.image,
                title: '画像フォルダ',
                subtitle: imageFolderPath ?? '選択されていません',
                onPressed: () => pickFolder(true),
              ),
              const SizedBox(height: 20),
              _buildFolderSelector(
                icon: Icons.favorite,
                title: 'お気に入りフォルダ',
                subtitle: favoriteFolderPath ?? '選択されていません',
                onPressed: () => pickFolder(false),
              ),
              const SizedBox(height: 40),
              if (imageFolderPath != null &&
                  favoriteFolderPath != null &&
                  imageFolderPath != favoriteFolderPath)
                SizedBox(
                  width: 200,
                  height: 50,
                  child: ElevatedButton.icon(
                    onPressed: navigateToImageDisplayPage,
                    icon: const Icon(Icons.photo_library, size: 24),
                    label: const Text(
                      '画像を表示',
                      style: TextStyle(fontSize: 18),
                    ),
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 20, vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  ),
                )
              else
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Text(
                    imageFolderPath == null || favoriteFolderPath == null
                        ? '画像フォルダとお気に入りフォルダを選択してください'
                        : '画像フォルダとお気に入りフォルダは異なるフォルダを選択してください',
                    style: const TextStyle(color: Colors.red),
                    textAlign: TextAlign.center,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFolderSelector({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onPressed,
  }) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 600),
        child: Card(
          elevation: 4,
          child: ListTile(
            leading: Icon(icon, size: 40),
            title: Text(title,
                style: const TextStyle(fontWeight: FontWeight.bold)),
            subtitle: Text(subtitle, style: const TextStyle(fontSize: 12)),
            trailing: const Icon(Icons.folder_open),
            onTap: onPressed,
          ),
        ),
      ),
    );
  }
}

class ImagePreloader {
  final Map<String, _PreloadInfo> _preloadedImages = {};
  final int _maxPreloadedImages = maxPreloadedImages;
  int _currentIndex = 0;
  List<File> _imageFiles = [];

  void logPreloadedImages() {
    if (_preloadedImages.isEmpty) {
      logger.d('No images preloaded.');
      return;
    }

    // プリロードされた画像を優先度順（低い順）にソート
    final sortedEntries = _preloadedImages.entries.toList()
      ..sort((a, b) => a.value.priority.compareTo(b.value.priority));

    List<String> fileNames = [];
    List<int> priorities = [];
    List<DateTime> timestamps = [];
    for (var entry in sortedEntries) {
      final imagePath = entry.key;
      final priority = entry.value.priority;
      final timestamp = entry.value.timestamp;

      // ファイル名のみを取得（フルパスではなく）
      final fileName = path.basename(imagePath);

      fileNames.add(fileName);
      priorities.add(priority);
      timestamps.add(timestamp);
    }

    logger.d(
        'Preloaded images: \n fileNames:$fileNames \n priorities:$priorities \n timestamps:$timestamps \n Total preloaded images:${_preloadedImages.length}');
  }

  void setCurrentIndex(int index, List<File> imageFiles) {
    logger.d(
        'Setting current index to $index. Total images: ${imageFiles.length}');
    _currentIndex = index;
    _imageFiles = imageFiles;
    _updatePriorities();
  }

  Future<void> preloadImages(BuildContext context) async {
    const preloadRange = maxPreloadedImages ~/ 2;
    logger.d(
        'Starting preload around index $_currentIndex (range: ±$preloadRange)');
    final preloadTasks = <Future>[];
    if (_imageFiles.isEmpty) {
      logger.w('No images to preload');
      return;
    }

    for (int i = -preloadRange; i <= preloadRange; i++) {
      if (i == 0) continue;
      final index =
          (_currentIndex + i + _imageFiles.length) % _imageFiles.length;
      final file = _imageFiles[index];
      final imagePath = file.path;

      if (!_preloadedImages.containsKey(imagePath)) {
        preloadTasks.add(_preloadImage(file, context, i.abs()));
      } else {
        _preloadedImages[imagePath]!.priority = i.abs();
      }
    }
    logger.d('preload tasks created: ${preloadTasks.length}');
    try {
      await Future.wait(preloadTasks).timeout(const Duration(seconds: 30));
      logger.d('All preload tasks completed successfully');
    } on TimeoutException catch (e) {
      logger.w('preloading images timed out: $e');
    } catch (e) {
      logger.e('Unexpected error while preloading images: $e');
    }
    _cleanupOldPreloads();
    logPreloadedImages();
  }

  Future<void> _preloadImage(
      File file, BuildContext context, int priority) async {
    final imagePath = file.path;
    if (context.mounted) {
      bool success = true;
      try {
        await precacheImage(
          FileImage(file),
          context,
          onError: (exception, stackTrace) {
            success = false;
            logger.w(
                'Failed to preload image. The file may be corrupted: $imagePath  $exception');
          },
        ).timeout(const Duration(seconds: 5));
      } on TimeoutException catch (e) {
        success = false;
        logger.w('preloading image timed out for image: $imagePath  $e');
      } catch (exception) {
        success = false;
        logger.w(
            'Unexpected error while preloading image: $imagePath  $exception');
      }

      if (success) {
        _preloadedImages[imagePath] = _PreloadInfo(
          DateTime.now(),
          priority,
        );
      }
    }
  }

  void _updatePriorities() {
    logger.d(
        'Updating priorities for ${_preloadedImages.length} preloaded images');
    int updatedCount = 0;
    for (var entry in _preloadedImages.entries) {
      final index = _imageFiles.indexWhere((file) => file.path == entry.key);
      if (index != -1) {
        final oldPriority = entry.value.priority;
        final distance = (index - _currentIndex).abs();
        entry.value.priority = distance;

        if (oldPriority != distance) {
          updatedCount++;
        }
      }
    }
    logger.d('Updated priorities for $updatedCount images');
  }

  void _cleanupOldPreloads() {
    if (_preloadedImages.length <= _maxPreloadedImages) {
      logger.d(
          'No cleanup needed. Current preloaded images: ${_preloadedImages.length}');
      return;
    }

    logger.d(
        'starting cleanup. Current preloaded images: ${_preloadedImages.length}');
    final sortedEntries = _preloadedImages.entries.toList()
      ..sort((a, b) {
        // 優先度が高い（値が小さい）ほど、後ろに配置
        int priorityComparison = b.value.priority.compareTo(a.value.priority);
        if (priorityComparison != 0) return priorityComparison;
        // 優先度が同じ場合は、古い順に並べる
        return a.value.timestamp.compareTo(b.value.timestamp);
      });
    final imagesToRemove = sortedEntries.length - _maxPreloadedImages;
    logger.d('Removing $imagesToRemove images from preloaded images');

    // 優先度が低く、古い画像から削除
    for (var i = 0; i < imagesToRemove; i++) {
      final removeImage = sortedEntries[i].key;
      _preloadedImages.remove(removeImage);
      logger.d(
          'Removed image from preloaded images: ${path.basename(removeImage)}');
    }
    logger.d(
        'Cleanup completed. Current preloaded images: ${_preloadedImages.length}');
  }

  bool isImagePreloaded(String imagePath) {
    bool isPreloaded = _preloadedImages.containsKey(imagePath);
    logger.d('Checking if image is preloaded: $imagePath -> $isPreloaded');
    return isPreloaded;
  }
}

class _PreloadInfo {
  DateTime timestamp;
  int priority;

  _PreloadInfo(this.timestamp, this.priority);
}

class ImageDisplayPage extends StatefulWidget {
  final String imageFolderPath;
  final String favoriteFolderPath;

  const ImageDisplayPage({
    super.key,
    required this.imageFolderPath,
    required this.favoriteFolderPath,
  });

  @override
  ImageDisplayPageState createState() => ImageDisplayPageState();
}

class ImageDisplayPageState extends State<ImageDisplayPage>
    with WindowListener {
  final ImagePreloader _imagePreloader = ImagePreloader();
  bool _isFullScreen = false;
  bool _isControlBarVisible = true;
  DateTime _lastImageFolderCheck = DateTime.now();
  DateTime _lastFavoriteFolderCheck = DateTime.now();
  late List<File> imageFiles;
  late Set<String> favoriteFiles;
  int currentIndex = 0;
  final TextEditingController _currentIndexController = TextEditingController();

  Future<bool> _hasImageFolderChanged() async {
    final directory = Directory(widget.imageFolderPath);
    final lastModified = directory.statSync().modified;
    if (lastModified.isAfter(_lastImageFolderCheck)) {
      _lastImageFolderCheck = DateTime.now();
      return true;
    }
    return false;
  }

  Future<bool> _hasFavoriteFolderChanged() async {
    final directory = Directory(widget.favoriteFolderPath);
    final lastModified = directory.statSync().modified;
    if (lastModified.isAfter(_lastFavoriteFolderCheck)) {
      _lastFavoriteFolderCheck = DateTime.now();
      return true;
    }
    return false;
  }

  Future<void> _preloadedImage(int index) async {
    _imagePreloader.setCurrentIndex(index, imageFiles);
    await _imagePreloader.preloadImages(context);
  }

  @override
  void initState() {
    super.initState();
    logger.i('Initializing ImageDisplayPage');
    windowManager.addListener(this);
    PaintingBinding.instance.imageCache.maximumSize = maxPreloadedImages;
    imageFiles = Directory(widget.imageFolderPath)
        .listSync()
        .where((item) => item is File && _isImageFile(item.path))
        .map((item) => item as File)
        .toList();
    logger.i('Number of images found: ${imageFiles.length}');
    _currentIndexController.text = (currentIndex + 1).toString();
    favoriteFiles = Directory(widget.favoriteFolderPath)
        .listSync()
        .where((item) => item is File && _isImageFile(item.path))
        .map((item) => path.basename(item.path))
        .toSet();
    logger.i('Number of favorite images found: ${favoriteFiles.length}');
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _preloadedImage(currentIndex);
    });
  }

  @override
  void dispose() {
    PaintingBinding.instance.imageCache.clear();
    PaintingBinding.instance.imageCache.clearLiveImages();
    windowManager.removeListener(this);
    super.dispose();
  }

  bool _isImageFile(String path) {
    final extension = path.split('.').last.toLowerCase();
    return ['png', 'jpg', 'jpeg', 'bmp', 'webp'].contains(extension);
  }

  void _toggleControlBar() {
    setState(() {
      _isControlBarVisible = !_isControlBarVisible;
    });
  }

  Future<void> _toggleFullScreen() async {
    _isFullScreen = !_isFullScreen;
    if (_isFullScreen) {
      await windowManager.setFullScreen(true);
      await windowManager.setTitleBarStyle(TitleBarStyle.hidden);
    } else {
      await windowManager.setFullScreen(false);
      await windowManager.setTitleBarStyle(TitleBarStyle.normal);
    }
    setState(() {});
  }

  Future<void> _scanFavoriteFolder() async {
    final directory = Directory(widget.favoriteFolderPath);
    if (!directory.existsSync()) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('お気に入りフォルダが見つかりません')),
        );
      }
      return;
    }

    try {
      if (await _hasFavoriteFolderChanged()) {
        final newFavoriteFiles = directory
            .listSync()
            .where((item) => item is File && _isImageFile(item.path))
            .map((item) => path.basename(item.path))
            .toSet();

        if (!setEquals(favoriteFiles, newFavoriteFiles)) {
          setState(() {
            favoriteFiles = newFavoriteFiles;
          });
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('お気に入りフォルダのスキャンに失敗しました: $e')),
        );
      }
    }
  }

  Future<void> _reloadImageFolder() async {
    final directory = Directory(widget.imageFolderPath);
    if (!directory.existsSync()) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('画像フォルダが見つかりません')),
        );
      }
      setState(() {
        imageFiles = [];
      });
      return;
    }

    try {
      if (await _hasImageFolderChanged()) {
        final newImageFiles = directory
            .listSync()
            .where((item) => item is File && _isImageFile(item.path))
            .map((item) => item as File)
            .toList();

        if (!const ListEquality().equals(imageFiles, newImageFiles)) {
          setState(() {
            imageFiles = newImageFiles;
          });
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('画像フォルダの再読み込みに失敗しました: $e')),
        );
      }
    }
  }

  Future<void> _showNextImage() async {
    await _reloadImageFolder();
    await _scanFavoriteFolder();
    if (currentIndex < imageFiles.length - 1) {
      setState(() {
        currentIndex++;
        _currentIndexController.text = (currentIndex + 1).toString();
      });
      logger.i({
        'show next image': {
          'next image index': currentIndex,
          'next image path': imageFiles[currentIndex].path,
        }
      });
      // await _preloadedImage(currentIndex);
      _preloadedImage(currentIndex); //dont wait
    }
    // _reloadImageFolder();//dont wait
    // _scanFavoriteFolder();//dont wait
  }

  Future<void> _showPreviousImage() async {
    await _reloadImageFolder(); //wait
    await _scanFavoriteFolder(); //wait
    if (currentIndex > 0) {
      setState(() {
        currentIndex--;
        _currentIndexController.text = (currentIndex + 1).toString();
      });
      logger.i({
        'show previous image': {
          'previous image index': currentIndex,
          'previous image path': imageFiles[currentIndex].path,
        }
      });
      // await _preloadedImage(currentIndex); //wait
      _preloadedImage(currentIndex); //dont wait
    }
    // _reloadImageFolder();//dont wait
    // _scanFavoriteFolder();//dont wait
  }

  Future<void> _updateCurrentIndex() async {
    await _reloadImageFolder(); //wait
    await _scanFavoriteFolder(); //wait
    if (imageFiles.isEmpty) return;
    final newIndex = int.tryParse(_currentIndexController.text) ?? 0;
    if (newIndex > 0 && newIndex <= imageFiles.length) {
      setState(() {
        currentIndex = newIndex - 1;
      });
      logger.i({
        'update current index': {
          'new index': currentIndex,
          'new image path': imageFiles[currentIndex].path,
        }
      });
      // await _preloadedImage(currentIndex); //wait
      _preloadedImage(currentIndex); //dont wait
    } else {
      logger.w('Invalid index entered: $newIndex');
      if (!mounted) return;
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('エラー'),
          content: const Text('有効なインデックスを入力してください。'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('OK'),
            ),
          ],
        ),
      );
    }
    // _reloadImageFolder();//dont wait
    // _scanFavoriteFolder();//dont wait
  }

  Future<void> _saveToFavorites() async {
    try {
      final currentImage = imageFiles[currentIndex];
      final fileName = path.basename(currentImage.path);
      final destinationPath = path.join(widget.favoriteFolderPath, fileName);
      await currentImage.copy(destinationPath);
      logger.i('Saved image to favorites: $destinationPath');
      _scanFavoriteFolder();
    } catch (e) {
      logger.e('Failed to save image to favorites: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('エラー: お気に入りの保存に失敗しました - $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    WidgetsBinding.instance.deferFirstFrame();
    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      body: Shortcuts(
        shortcuts: {
          LogicalKeySet(LogicalKeyboardKey.arrowRight): const NextImageIntent(),
          LogicalKeySet(LogicalKeyboardKey.arrowLeft):
              const PreviousImageIntent(),
          LogicalKeySet(LogicalKeyboardKey.space): const SaveImageIntent(),
        },
        child: Actions(
          actions: <Type, Action<Intent>>{
            NextImageIntent: CallbackAction<NextImageIntent>(
              onInvoke: (NextImageIntent intent) => _showNextImage(),
            ),
            PreviousImageIntent: CallbackAction<PreviousImageIntent>(
              onInvoke: (PreviousImageIntent intent) => _showPreviousImage(),
            ),
            SaveImageIntent: CallbackAction<SaveImageIntent>(
              onInvoke: (SaveImageIntent intent) => _saveToFavorites(),
            ),
          },
          child: Focus(
            autofocus: true,
            child: Center(
              child: imageFiles.isEmpty
                  ? _buildEmptyStateView()
                  : Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Expanded(child: _buildImageViewer()),
                        _buildControlBar(),
                      ],
                    ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyStateView() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Text('画像が見つかりませんでした。', style: TextStyle(color: Colors.white)),
          const SizedBox(height: 20),
          IconButton(
            icon: const Icon(Icons.home),
            color: Colors.white,
            onPressed: () async {
              await windowManager.setFullScreen(false);
              await windowManager.setTitleBarStyle(TitleBarStyle.normal);
              if (!mounted) return;
              Navigator.pop(context);
            },
          ),
        ],
      ),
    );
  }

  Widget _buildImageViewer() {
    return GestureDetector(
      onTap: _toggleControlBar,
      child: Stack(
        children: [
          Container(
            color: const Color(0xFF121212),
            child: InteractiveViewer(
              minScale: 0.1,
              maxScale: 10.0,
              child: Image(
                gaplessPlayback: true,
                image: FileImage(imageFiles[currentIndex]),
                width: double.infinity,
                height: double.infinity,
                errorBuilder: _buildImageErrorWidget,
                loadingBuilder: _buildImageLoadingWidget,
              ),
            ),
          ),
          _buildFavoriteIcon(),
        ],
      ),
    );
  }

  Widget _buildFavoriteIcon() {
    if (!favoriteFiles.contains(path.basename(imageFiles[currentIndex].path))) {
      return const SizedBox.shrink();
    }
    return Positioned(
      top: 10,
      right: 10,
      child: Container(
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
        ),
        child: const Icon(
          Icons.favorite,
          color: Colors.red,
          size: 36,
        ),
      ),
    );
  }

  Widget _buildControlBar() {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      height: _isControlBarVisible ? 50 : 0,
      color: const Color(0xFF121212),
      child: _isControlBarVisible
          ? Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _buildHomeButton(),
                const SizedBox(width: 10),
                _buildFullScreenButton(),
                const SizedBox(width: 10),
                _showPreviousImageButton(),
                _buildImageCounter(),
                _showNextImageButton(),
                _buildFavoriteButton(),
              ],
            )
          : null,
    );
  }

  Widget _buildHomeButton() {
    return IconButton(
      icon: const Icon(Icons.home),
      color: Colors.white,
      onPressed: () async {
        await windowManager.setFullScreen(false);
        await windowManager.setTitleBarStyle(TitleBarStyle.normal);
        if (!mounted) return;
        Navigator.pop(context);
      },
    );
  }

  Widget _buildFullScreenButton() {
    return IconButton(
      icon: Icon(_isFullScreen ? Icons.fullscreen_exit : Icons.fullscreen),
      color: Colors.white,
      onPressed: _toggleFullScreen,
    );
  }

  Widget _showNextImageButton() {
    return IconButton(
      icon: const Icon(Icons.arrow_forward),
      color: Colors.white,
      onPressed: _showNextImage,
    );
  }

  Widget _showPreviousImageButton() {
    return IconButton(
      icon: const Icon(Icons.arrow_back),
      onPressed: _showPreviousImage,
      color: Colors.white,
    );
  }

  Widget _buildImageCounter() {
    return Row(
      children: [
        SizedBox(
          width: 100,
          child: TextField(
            controller: _currentIndexController,
            decoration: const InputDecoration(
              filled: true,
              fillColor: Color(0xFF121212),
              hoverColor: Color(0xFF323232),
              border: OutlineInputBorder(
                borderSide: BorderSide.none,
                borderRadius: BorderRadius.all(Radius.zero),
              ),
            ),
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            onSubmitted: (_) => _updateCurrentIndex(),
            textAlign: TextAlign.right,
            style: const TextStyle(color: Colors.white, fontSize: 18),
          ),
        ),
        const Text('/', style: TextStyle(color: Colors.white, fontSize: 18)),
        SizedBox(
          width: 100,
          child: TextField(
            enabled: false,
            controller:
                TextEditingController(text: imageFiles.length.toString()),
            decoration: const InputDecoration(
              filled: true,
              fillColor: Color(0xFF121212),
            ),
            keyboardType: TextInputType.number,
            textAlign: TextAlign.left,
            style: const TextStyle(color: Colors.white, fontSize: 18),
          ),
        ),
      ],
    );
  }

  Widget _buildFavoriteButton() {
    return IconButton(
      icon: Icon(
        Icons.favorite,
        color:
            favoriteFiles.contains(path.basename(imageFiles[currentIndex].path))
                ? Colors.red
                : Colors.white,
      ),
      onPressed: _saveToFavorites,
    );
  }

  Widget _buildImageErrorWidget(
      BuildContext context, Object error, StackTrace? stackTrace) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.broken_image, size: 64, color: Colors.red),
          const SizedBox(height: 16),
          Text(
            'この画像を開けません。ファイルが破損しているか、サポートされていない形式です。\n${path.basename(imageFiles[currentIndex].path)}',
            style: const TextStyle(color: Colors.white),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildImageLoadingWidget(
      BuildContext context, Widget child, ImageChunkEvent? loadingProgress) {
    if (loadingProgress == null) {
      return child;
    }
    return Center(
      child: CircularProgressIndicator(
        value: loadingProgress.expectedTotalBytes != null
            ? loadingProgress.cumulativeBytesLoaded /
                loadingProgress.expectedTotalBytes!
            : null,
      ),
    );
  }
}

class NextImageIntent extends Intent {
  const NextImageIntent();
}

class PreviousImageIntent extends Intent {
  const PreviousImageIntent();
}

class SaveImageIntent extends Intent {
  const SaveImageIntent();
}
