import 'package:flutter/material.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:dio/dio.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'API Practice',
      theme: ThemeData(primarySwatch: Colors.blue, useMaterial3: true),
      home: const HomePage(),
      debugShowCheckedModeBanner: false, // Thêm dòng này để tắt banner debug
    );
  }
}

// Models
class Post {
  final int id;
  final int userId;
  final String title;
  final String body;

  Post({
    required this.id,
    required this.userId,
    required this.title,
    required this.body,
  });

  factory Post.fromJson(Map<String, dynamic> json) {
    return Post(
      id: json['id'],
      userId: json['userId'],
      title: json['title'],
      body: json['body'],
    );
  }
}

// HTTP Service
class HttpService {
  static const String baseUrl = 'https://jsonplaceholder.typicode.com';

  Future<List<Post>> fetchPosts() async {
    try {
      final response = await http
          .get(
            Uri.parse('$baseUrl/posts'),
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer fake_token_for_demo', // Auth thủ công
            },
          )
          .timeout(
            const Duration(seconds: 10),
            onTimeout: () {
              // Timeout thủ công
              throw Exception('Request timeout');
            },
          );

      if (response.statusCode == 200) {
        List<dynamic> data = json.decode(response.body); // Parse JSON thủ công
        return data.map((json) => Post.fromJson(json)).toList();
      } else {
        // Error handling thủ công
        throw Exception('Failed to load posts: ${response.statusCode}');
      }
    } catch (e) {
      throw Exception('Error fetching posts: $e');
    }
  }

  Future<Post> fetchPostById(int id) async {
    final response = await http.get(
      Uri.parse('$baseUrl/posts/$id'),
      headers: {'Authorization': 'Bearer fake_token_for_demo'}, // Auth thủ công
    );

    if (response.statusCode == 200) {
      return Post.fromJson(json.decode(response.body)); // Parse JSON thủ công
    } else {
      throw Exception('Failed to load post'); // Error handling thủ công
    }
  }
}

// Dio Service with Interceptors
class DioService {
  static const String baseUrl = 'https://jsonplaceholder.typicode.com';
  late Dio _dio;

  DioService() {
    _dio = Dio(
      BaseOptions(
        baseUrl: baseUrl,
        connectTimeout: const Duration(seconds: 10), // Timeout có sẵn
        receiveTimeout: const Duration(seconds: 10), // Timeout có sẵn
        headers: {'Content-Type': 'application/json'},
      ),
    );

    // Thêm Interceptors
    _dio.interceptors.add(AuthInterceptor()); // Xử lý Authentication
    _dio.interceptors.add(LoggingInterceptor());
    _dio.interceptors.add(RetryInterceptor(dio: _dio)); // Xử lý Retry
  }

  Future<List<Post>> fetchPosts() async {
    try {
      final response = await _dio.get('/posts');
      List<dynamic> data = response.data; // Tự động parse JSON
      return data.map((json) => Post.fromJson(json)).toList();
    } on DioException catch (e) {
      throw _handleError(e); // Error handling tập trung
    }
  }

  Future<Post> fetchPostById(int id) async {
    try {
      final response = await _dio.get('/posts/$id');
      return Post.fromJson(response.data); // Tự động parse JSON
    } on DioException catch (e) {
      throw _handleError(e); // Error handling tập trung
    }
  }

  // Error handling chi tiết
  String _handleError(DioException e) {
    switch (e.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
        return 'Connection timeout';
      case DioExceptionType.badResponse:
        return 'Server error: ${e.response?.statusCode}';
      case DioExceptionType.cancel:
        return 'Request cancelled';
      default:
        return 'Network error: ${e.message}';
    }
  }
}

// Authentication Interceptor (Đáp ứng yêu cầu 3)
class AuthInterceptor extends Interceptor {
  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    // Tự động thêm token vào TẤT CẢ request
    options.headers['Authorization'] = 'Bearer fake_token_for_demo';
    print('🔐 Auth token added to request');
    handler.next(options);
  }
}

// Logging Interceptor (Hữu ích để demo)
class LoggingInterceptor extends Interceptor {
  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    print('📤 REQUEST: ${options.method} ${options.path}');
    handler.next(options);
  }

  @override
  void onResponse(Response response, ResponseInterceptorHandler handler) {
    print(
      '📥 RESPONSE: ${response.statusCode} ${response.requestOptions.path}',
    );
    handler.next(response);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    print('❌ ERROR: ${err.message}');
    handler.next(err);
  }
}

// Retry Interceptor (Đáp ứng yêu cầu 4)
class RetryInterceptor extends Interceptor {
  final Dio dio;
  final int maxRetries;

  RetryInterceptor({required this.dio, this.maxRetries = 3});

  @override
  Future<void> onError(
    DioException err,
    ErrorInterceptorHandler handler,
  ) async {
    if (_shouldRetry(err)) {
      int retryCount = err.requestOptions.extra['retryCount'] ?? 0;

      if (retryCount < maxRetries) {
        retryCount++;
        err.requestOptions.extra['retryCount'] = retryCount;

        print('🔄 Retry attempt $retryCount of $maxRetries');

        // Chờ trước khi thử lại
        await Future.delayed(Duration(seconds: retryCount));

        try {
          final response = await dio.fetch(err.requestOptions);
          return handler.resolve(response);
        } catch (e) {
          return super.onError(err, handler);
        }
      }
    }
    return super.onError(err, handler);
  }

  // Chỉ thử lại nếu là lỗi kết nối/timeout
  bool _shouldRetry(DioException err) {
    return err.type == DioExceptionType.connectionTimeout ||
        err.type == DioExceptionType.receiveTimeout ||
        err.type == DioExceptionType.unknown;
  }
}

// Home Page (UI)
class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final HttpService _httpService = HttpService();
  final DioService _dioService = DioService();

  List<Post> _posts = [];
  bool _isLoading = false;
  String _error = '';
  String _currentService = 'Dio'; // Bắt đầu bằng Dio để thấy rõ Interceptor

  @override
  void initState() {
    super.initState();
    _loadPosts();
  }

  Future<void> _loadPosts() async {
    setState(() {
      _isLoading = true;
      _error = '';
      _posts = []; // Xóa list cũ
    });

    try {
      List<Post> posts;
      if (_currentService == 'HTTP') {
        posts = await _httpService.fetchPosts();
      } else {
        posts = await _dioService.fetchPosts();
      }

      setState(() {
        _posts = posts;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  void _switchService() {
    setState(() {
      _currentService = _currentService == 'HTTP' ? 'Dio' : 'HTTP';
    });
    _loadPosts();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('HTTP vs Dio Demo'),
        elevation: 2,
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 8.0),
            child: Chip(
              label: Text(_currentService),
              backgroundColor: _currentService == 'Dio'
                  ? Colors.blue.shade100
                  : Colors.green.shade100,
            ),
          ),
          IconButton(
            icon: const Icon(Icons.swap_horiz),
            onPressed: _switchService,
            tooltip: 'Switch to ${_currentService == 'HTTP' ? 'Dio' : 'HTTP'}',
          ),
        ],
      ),
      body: Column(
        children: [
          // Info Card (Giải thích tính năng)
          Container(
            width: double.infinity,
            margin: const EdgeInsets.all(16),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.blue.shade50,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.blue.shade200),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Current Service: $_currentService',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 😎,
                Text(
                  _currentService == 'Dio'
                      ? '✓ Tự động Parse JSON\n✓ Interceptor (Auth, Log, Retry)\n✓ Error Handling (DioException)\n✓ Timeout có sẵn'
                      : '✓ Parse JSON (jsonDecode)\n✓ Auth/Timeout (Thủ công)\n✓ Error Handling (Thủ công)',
                  style: TextStyle(fontSize: 13, color: Colors.grey.shade700),
                ),
              ],
            ),
          ),

          // Posts List
          Expanded(
            child: _isLoading
                ? const Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        CircularProgressIndicator(),
                        SizedBox(height: 16),
                        Text('Loading posts...'),
                      ],
                    ),
                  )
                : _error.isNotEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(
                            Icons.error_outline,
                            size: 64,
                            color: Colors.red,
                          ),
                          const SizedBox(height: 16),
                          Text(
                            'Error',
                            style: Theme.of(context).textTheme.headlineSmall,
                          ),
                          const SizedBox(height: 😎,
                          Text(
                            _error,
                            textAlign: TextAlign.center,
                            style: const TextStyle(color: Colors.red),
                          ),
                          const SizedBox(height: 24),
                          ElevatedButton.icon(
                            onPressed: _loadPosts,
                            icon: const Icon(Icons.refresh),
                            label: const Text('Retry'),
                          ),
                        ],
                      ),
                    ),
                  )
                : RefreshIndicator(
                    onRefresh: _loadPosts,
                    child: ListView.builder(
                      itemCount: _posts.length,
                      padding: const EdgeInsets.all(😎,
                      itemBuilder: (context, index) {
                        final post = _posts[index];
                        return Card(
                          margin: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          child: ListTile(
                            leading: CircleAvatar(
                              backgroundColor: Colors.blue,
                              child: Text(
                                '${post.id}',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                            title: Text(
                              post.title,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            subtitle: Text(
                              post.body,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                            trailing: Chip(
                              label: Text('User ${post.userId}'),
                              backgroundColor: Colors.grey.shade200,
                            ),
                            onTap: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) => PostDetailPage(
                                    postId: post.id,
                                    service: _currentService,
                                    httpService: _httpService,
                                    dioService: _dioService,
                                  ),
                                ),
                              );
                            },
                          ),
                        );
                      },
                    ),
                  ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _loadPosts,
        tooltip: 'Refresh',
        child: const Icon(Icons.refresh),
      ),
    );
  }
}

// Post Detail Page
class PostDetailPage extends StatefulWidget {
  final int postId;
  final String service;
  final HttpService httpService;
  final DioService dioService;

  const PostDetailPage({
    super.key,
    required this.postId,
    required this.service,
    required this.httpService,
    required this.dioService,
  });

  @override
  State<PostDetailPage> createState() => _PostDetailPageState();
}

class _PostDetailPageState extends State<PostDetailPage> {
  Post? _post;
  bool _isLoading = true;
  String _error = '';

  @override
  void initState() {
    super.initState();
    _loadPost();
  }

  Future<void> _loadPost() async {
    setState(() {
      _isLoading = true;
      _error = '';
    });

    try {
      Post post;
      if (widget.service == 'HTTP') {
        post = await widget.httpService.fetchPostById(widget.postId);
      } else {
        post = await widget.dioService.fetchPostById(widget.postId);
      }

      setState(() {
        _post = post;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Post #${widget.postId}')),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _error.isNotEmpty
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.error, size: 64, color: Colors.red),
                  const SizedBox(height: 16),
                  Text(_error),
                  const SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: _loadPost,
                    child: const Text('Retry'),
                  ),
                ],
              ),
            )
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.blue.shade50,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.person, color: Colors.blue),
                        const SizedBox(width: 😎,
                        Text(
                          'User ID: ${_post!.userId}',
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                  Text(
                    _post!.title,
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    _post!.body,
                    style: const TextStyle(fontSize: 16, height: 1.5),
                  ),
                  const SizedBox(height: 24),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade100,
                      borderRadius: BorderRadius.circular(😎,
                    ),
                    child: Row(
                      children: [
                        Icon(
                          widget.service == 'Dio'
                              ? Icons.rocket_launch
                              : Icons.http,
                          size: 20,
                        ),
                        const SizedBox(width: 😎,
                        Text(
                          'Fetched using ${widget.service}',
                          style: TextStyle(
                            color: Colors.grey.shade700,
                            fontStyle: FontStyle.italic,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}