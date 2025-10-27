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
      theme: ThemeData(
        primarySwatch: Colors.blue,
        useMaterial3: true,
      ),
      home: const HomePage(),
    );
  }
}

// ==================== MODELS ====================
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

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'userId': userId,
      'title': title,
      'body': body,
    };
  }
}

// ==================== CUSTOM EXCEPTIONS ====================
class ApiException implements Exception {
  final String message;
  final int? statusCode;
  final dynamic data;

  ApiException(this.message, {this.statusCode, this.data});

  @override
  String toString() => 'ApiException: $message (Status: $statusCode)';
}

class NetworkException extends ApiException {
  NetworkException() : super('No internet connection');
}

class TimeoutException extends ApiException {
  TimeoutException() : super('Request timeout');
}

class UnauthorizedException extends ApiException {
  UnauthorizedException()
      : super('Unauthorized - Please login again', statusCode: 401);
}

class ForbiddenException extends ApiException {
  ForbiddenException() : super('Forbidden - No permission', statusCode: 403);
}

class NotFoundException extends ApiException {
  NotFoundException(String message) : super(message, statusCode: 404);
}

class ServerException extends ApiException {
  ServerException(String message, {int? statusCode})
      : super(message, statusCode: statusCode ?? 500);
}

class BadRequestException extends ApiException {
  BadRequestException(String message) : super(message, statusCode: 400);
}

// ==================== EXCEPTION HANDLER ====================
class ApiExceptionHandler {
  static ApiException handle(DioException error) {
    switch (error.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
        return TimeoutException();

      case DioExceptionType.connectionError:
        return NetworkException();

      case DioExceptionType.badResponse:
        return _handleResponseError(error.response);

      case DioExceptionType.cancel:
        return ApiException('Request was cancelled');

      default:
        return ApiException('Unexpected error: ${error.message}');
    }
  }

  static ApiException _handleResponseError(Response? response) {
    final statusCode = response?.statusCode;
    final data = response?.data;

    switch (statusCode) {
      case 400:
        return BadRequestException(data?.toString() ?? 'Bad request');
      case 401:
        return UnauthorizedException();
      case 403:
        return ForbiddenException();
      case 404:
        return NotFoundException('Resource not found');
      case 500:
        return ServerException('Internal server error', statusCode: 500);
      case 502:
        return ServerException('Bad gateway', statusCode: 502);
      case 503:
        return ServerException('Service unavailable', statusCode: 503);
      default:
        return ApiException(
          'Request failed',
          statusCode: statusCode,
          data: data,
        );
    }
  }
}

// ==================== TOKEN STORAGE ====================
class TokenStorage {
  String? _accessToken;
  String? _refreshToken;

  // Save access token
  Future<void> saveToken(String token) async {
    _accessToken = token;
    // In production: Save to SecureStorage or SharedPreferences
    print('Token saved: ${token.substring(0, 20)}...');
  }

  // Get access token
  Future<String?> getToken() async {
    return _accessToken;
  }

  // Save refresh token
  Future<void> saveRefreshToken(String token) async {
    _refreshToken = token;
    print('Refresh token saved');
  }

  // Get refresh token
  Future<String?> getRefreshToken() async {
    return _refreshToken;
  }

  // Delete all tokens (logout)
  Future<void> deleteTokens() async {
    _accessToken = null;
    _refreshToken = null;
    print('🗑️ All tokens deleted');
  }

  // Check if user is authenticated
  bool get isAuthenticated => _accessToken != null;
}

// ==================== HTTP SERVICE ====================
class HttpService {
  static const String baseUrl = 'https://jsonplaceholder.typicode.com';

  Future<List<Post>> fetchPosts() async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/posts'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer fake_token_for_demo',
        },
      ).timeout(
        const Duration(seconds: 10),
        onTimeout: () {
          throw TimeoutException();
        },
      );

      if (response.statusCode == 200) {
        List<dynamic> data = json.decode(response.body);
        return data.map((json) => Post.fromJson(json)).toList();
      } else {
        throw _handleHttpError(response.statusCode);
      }
    } catch (e) {
      if (e is ApiException) rethrow;
      throw ApiException('Error fetching posts: $e');
    }
  }

  Future<Post> fetchPostById(int id) async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/posts/$id'),
        headers: {'Authorization': 'Bearer fake_token_for_demo'},
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        return Post.fromJson(json.decode(response.body));
      } else {
        throw _handleHttpError(response.statusCode);
      }
    } catch (e) {
      if (e is ApiException) rethrow;
      throw ApiException('Error fetching post: $e');
    }
  }

  ApiException _handleHttpError(int statusCode) {
    switch (statusCode) {
      case 400:
        return BadRequestException('Bad request');
      case 401:
        return UnauthorizedException();
      case 403:
        return ForbiddenException();
      case 404:
        return NotFoundException('Post not found');
      case 500:
      case 502:
      case 503:
        return ServerException('Server error', statusCode: statusCode);
      default:
        return ApiException('HTTP Error', statusCode: statusCode);
    }
  }
}

// ==================== INTERCEPTORS ====================

// Authentication Interceptor
class AuthInterceptor extends Interceptor {
  final TokenStorage tokenStorage;

  AuthInterceptor(this.tokenStorage);

  @override
  void onRequest(
      RequestOptions options, RequestInterceptorHandler handler) async {
    // Get token from storage
    final token = await tokenStorage.getToken();

    if (token != null) {
      options.headers['Authorization'] = 'Bearer $token';
      print(' Auth token added to request');
    } else {
      // Use demo token if no real token
      options.headers['Authorization'] = 'Bearer fake_token_for_demo';
      print(' Demo token added to request');
    }

    handler.next(options);
  }
}

// Logging Interceptor
class LoggingInterceptor extends Interceptor {
  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    print('REQUEST: ${options.method} ${options.path}');
    print('   Headers: ${options.headers}');
    if (options.data != null) {
      print('   Data: ${options.data}');
    }
    handler.next(options);
  }

  @override
  void onResponse(Response response, ResponseInterceptorHandler handler) {
    print('RESPONSE: ${response.statusCode} ${response.requestOptions.path}');
    print('   Data length: ${response.data.toString().length} chars');
    handler.next(response);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    print('ERROR: ${err.type}');
    print('Message: ${err.message}');
    if (err.response != null) {
      print('   Status: ${err.response?.statusCode}');
    }
    handler.next(err);
  }
}

// Retry Interceptor with Exponential Backoff
class RetryInterceptor extends Interceptor {
  final Dio dio;
  final int maxRetries;
  final Duration initialDelay;

  RetryInterceptor({
    required this.dio,
    this.maxRetries = 3,
    this.initialDelay = const Duration(seconds: 1),
  });

  @override
  Future<void> onError(
      DioException err, ErrorInterceptorHandler handler) async {
    if (!_shouldRetry(err)) {
      return super.onError(err, handler);
    }

    final retryCount = err.requestOptions.extra['retryCount'] ?? 0;

    if (retryCount >= maxRetries) {
      print('Max retries ($maxRetries) exceeded');
      return super.onError(err, handler);
    }

    // Exponential backoff: delay = initialDelay * (2 ^ retryCount)
    final delay = initialDelay * (1 << retryCount);
    print(
        ' Retry attempt ${retryCount + 1}/$maxRetries after ${delay.inSeconds}s');

    await Future.delayed(delay);

    // Clone request and increment retry count
    final opts = err.requestOptions;
    opts.extra['retryCount'] = retryCount + 1;

    try {
      final response = await dio.fetch(opts);
      return handler.resolve(response);
    } catch (e) {
      return super.onError(err, handler);
    }
  }

  bool _shouldRetry(DioException err) {
    // Retry only for specific error types and 5xx server errors
    return err.type == DioExceptionType.connectionError ||
        err.type == DioExceptionType.connectionTimeout ||
        err.type == DioExceptionType.receiveTimeout ||
        (err.response?.statusCode ?? 0) >= 500;
  }
}

// Refresh Token Interceptor
class RefreshTokenInterceptor extends Interceptor {
  final Dio dio;
  final TokenStorage tokenStorage;

  RefreshTokenInterceptor(this.dio, this.tokenStorage);

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) async {
    // If 401 Unauthorized, try to refresh token
    if (err.response?.statusCode == 401) {
      print('Token expired, attempting refresh...');

      try {
        final refreshToken = await tokenStorage.getRefreshToken();

        if (refreshToken != null) {
          // Call refresh token API
          final response = await dio.post(
            '/auth/refresh',
            data: {'refresh_token': refreshToken},
            options: Options(
              headers: {'Authorization': 'Bearer $refreshToken'},
            ),
          );

          if (response.statusCode == 200) {
            final newAccessToken = response.data['access_token'];
            final newRefreshToken = response.data['refresh_token'];

            // Save new tokens
            await tokenStorage.saveToken(newAccessToken);
            if (newRefreshToken != null) {
              await tokenStorage.saveRefreshToken(newRefreshToken);
            }

            print('Token refreshed successfully');

            // Retry original request with new token
            final opts = err.requestOptions;
            opts.headers['Authorization'] = 'Bearer $newAccessToken';

            final cloneReq = await dio.fetch(opts);
            return handler.resolve(cloneReq);
          }
        }
      } catch (e) {
        print('Token refresh failed: $e');
        // Refresh failed, clear tokens
        await tokenStorage.deleteTokens();
        return handler.reject(err);
      }
    }

    super.onError(err, handler);
  }
}

// ==================== DIO SERVICE ====================
class DioService {
  static const String baseUrl = 'https://jsonplaceholder.typicode.com';
  late final Dio _dio;
  final TokenStorage _tokenStorage = TokenStorage();

  DioService() {
    _dio = Dio(BaseOptions(
      baseUrl: baseUrl,
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 10),
      headers: {
        'Content-Type': 'application/json',
      },
    ));

    // Add interceptors in order
    _dio.interceptors.addAll([
      LoggingInterceptor(),
      AuthInterceptor(_tokenStorage),
      RefreshTokenInterceptor(_dio, _tokenStorage),
      RetryInterceptor(dio: _dio, maxRetries: 3),
    ]);
  }

  // Login method
  Future<void> login(String email, String password) async {
    try {
      final response = await _dio.post('/auth/login', data: {
        'email': email,
        'password': password,
      });

      if (response.statusCode == 200) {
        final accessToken =
            response.data['access_token'] ?? 'demo_access_token';
        final refreshToken =
            response.data['refresh_token'] ?? 'demo_refresh_token';

        await _tokenStorage.saveToken(accessToken);
        await _tokenStorage.saveRefreshToken(refreshToken);

        print('Login successful');
      }
    } on DioException catch (e) {
      throw ApiExceptionHandler.handle(e);
    }
  }

  // Logout method
  Future<void> logout() async {
    await _tokenStorage.deleteTokens();
    print('Logged out successfully');
  }

  // Check authentication status
  bool get isAuthenticated => _tokenStorage.isAuthenticated;

  Future<List<Post>> fetchPosts() async {
    try {
      final response = await _dio.get('/posts');
      List<dynamic> data = response.data;
      return data.map((json) => Post.fromJson(json)).toList();
    } on DioException catch (e) {
      throw ApiExceptionHandler.handle(e);
    }
  }

  Future<Post> fetchPostById(int id) async {
    try {
      final response = await _dio.get('/posts/$id');
      return Post.fromJson(response.data);
    } on DioException catch (e) {
      throw ApiExceptionHandler.handle(e);
    }
  }

  Future<Post> createPost(Post post) async {
    try {
      final response = await _dio.post('/posts', data: post.toJson());
      return Post.fromJson(response.data);
    } on DioException catch (e) {
      throw ApiExceptionHandler.handle(e);
    }
  }

  Future<Post> updatePost(int id, Post post) async {
    try {
      final response = await _dio.put('/posts/$id', data: post.toJson());
      return Post.fromJson(response.data);
    } on DioException catch (e) {
      throw ApiExceptionHandler.handle(e);
    }
  }

  Future<void> deletePost(int id) async {
    try {
      await _dio.delete('/posts/$id');
    } on DioException catch (e) {
      throw ApiExceptionHandler.handle(e);
    }
  }
}

// ==================== HOME PAGE ====================
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
  String _currentService = 'Dio';

  @override
  void initState() {
    super.initState();
    _loadPosts();
  }

  Future<void> _loadPosts() async {
    setState(() {
      _isLoading = true;
      _error = '';
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
    } on NetworkException {
      setState(() {
        _error = '📡 No internet connection. Please check your network.';
        _isLoading = false;
      });
    } on TimeoutException {
      setState(() {
        _error = ' Request timeout. Please try again.';
        _isLoading = false;
      });
    } on UnauthorizedException {
      setState(() {
        _error = ' Unauthorized. Please login again.';
        _isLoading = false;
      });
    } on NotFoundException catch (e) {
      setState(() {
        _error = ' ${e.message}';
        _isLoading = false;
      });
    } on ServerException catch (e) {
      setState(() {
        _error = ' Server error (${e.statusCode}). Please try again later.';
        _isLoading = false;
      });
    } on ApiException catch (e) {
      setState(() {
        _error = ' ${e.message}';
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _error = ' Unexpected error: $e';
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
        title: const Text('RESTful API Practice'),
        elevation: 2,
        actions: [
          Chip(
            label: Text(_currentService),
            backgroundColor: _currentService == 'Dio'
                ? Colors.blue.shade100
                : Colors.green.shade100,
          ),
          const SizedBox(width: 8),
          IconButton(
            icon: const Icon(Icons.swap_horiz),
            onPressed: _switchService,
            tooltip: 'Switch to ${_currentService == 'HTTP' ? 'Dio' : 'HTTP'}',
          ),
        ],
      ),
      body: Column(
        children: [
          // Info Card
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
                const SizedBox(height: 8),
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
                              Icon(
                                _getErrorIcon(_error),
                                size: 64,
                                color: Colors.red,
                              ),
                              const SizedBox(height: 16),
                              Text(
                                'Error',
                                style:
                                    Theme.of(context).textTheme.headlineSmall,
                              ),
                              const SizedBox(height: 8),
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
                          padding: const EdgeInsets.all(8),
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

  IconData _getErrorIcon(String error) {
    if (error.contains('internet')) {
      return Icons.wifi_off;
    } else if (error.contains('timeout')) {
      return Icons.timer_off;
    } else if (error.contains('Unauthorized')) {
      return Icons.lock;
    } else if (error.contains('not found')) {
      return Icons.search_off;
    } else if (error.contains('Server')) {
      return Icons.cloud_off;
    }
    return Icons.error_outline;
  }
}

// ==================== POST DETAIL PAGE ====================
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
    } on ApiException catch (e) {
      setState(() {
        _error = e.message;
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
      appBar: AppBar(
        title: Text('Post #${widget.postId}'),
      ),
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
                            const SizedBox(width: 8),
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
                        style:
                            Theme.of(context).textTheme.headlineSmall?.copyWith(
                                  fontWeight: FontWeight.bold,
                                ),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        _post!.body,
                        style: const TextStyle(
                          fontSize: 16,
                          height: 1.5,
                        ),
                      ),
                      const SizedBox(height: 24),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.grey.shade100,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              widget.service == 'Dio'
                                  ? Icons.rocket_launch
                                  : Icons.http,
                              size: 20,
                            ),
                            const SizedBox(width: 8),
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
