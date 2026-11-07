
import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

void main() {
  runApp(const FlixoraApp());
}

const Color bg = Color(0xFF090A0F);
const Color panel = Color(0xFF191B25);
const Color red = Color(0xFFE50914);
const String imageBase = 'https://image.tmdb.org/t/p/';
const String apiKey = String.fromEnvironment('TMDB_API_KEY');

class Movie {
  final int id;
  final String title;
  final String year;
  final String overview;
  final String poster;
  final String backdrop;
  final double rating;
  final String genre;
  final String releaseDate;

  const Movie({
    required this.id,
    required this.title,
    required this.year,
    required this.overview,
    required this.poster,
    required this.backdrop,
    required this.rating,
    required this.genre,
    required this.releaseDate,
  });

  factory Movie.fromJson(Map<String, dynamic> json) {
    final date = (json['release_date'] ?? '').toString();
    return Movie(
      id: json['id'] ?? 0,
      title: (json['title'] ?? json['name'] ?? 'Unknown Movie').toString(),
      year: date.length >= 4 ? date.substring(0, 4) : 'N/A',
      releaseDate: date,
      overview: (json['overview'] ?? 'No description available.').toString(),
      poster: (json['poster_path'] ?? '').toString(),
      backdrop: (json['backdrop_path'] ?? '').toString(),
      rating: (json['vote_average'] as num?)?.toDouble() ?? 0,
      genre: 'Movie',
    );
  }

  String get posterUrl =>
      poster.isEmpty ? '' : '$imageBase/w500$poster';

  String get backdropUrl =>
      backdrop.isEmpty ? posterUrl : '$imageBase/w1280$backdrop';
}

class TmdbService {
  static const String base = 'https://api.themoviedb.org/3';

  static Future<List<Movie>> getMovies(String endpoint) async {
    if (apiKey.isEmpty) {
      throw Exception('TMDB API Key is missing. Check GitHub Secret and build.yml.');
    }

    final uri = Uri.parse('$base/$endpoint').replace(queryParameters: {
      'api_key': apiKey,
      'language': 'en-US',
      'page': '1',
    });

    final response = await http.get(uri).timeout(
      const Duration(seconds: 25),
    );

    if (response.statusCode != 200) {
      throw Exception('TMDB error: ${response.statusCode}');
    }

    final data = jsonDecode(response.body);
    final results = data['results'] as List? ?? [];

    return results
        .whereType<Map<String, dynamic>>()
        .map(Movie.fromJson)
        .toList();
  }

  static Future<List<Movie>> search(String query) async {
    if (apiKey.isEmpty) {
      throw Exception('TMDB API Key is missing.');
    }

    final uri = Uri.parse('$base/search/movie').replace(
      queryParameters: {
        'api_key': apiKey,
        'query': query,
        'language': 'en-US',
        'page': '1',
        'include_adult': 'false',
      },
    );

    final response = await http.get(uri).timeout(
      const Duration(seconds: 25),
    );

    if (response.statusCode != 200) {
      throw Exception('Search failed: ${response.statusCode}');
    }

    final data = jsonDecode(response.body);
    final results = data['results'] as List? ?? [];

    return results
        .whereType<Map<String, dynamic>>()
        .map(Movie.fromJson)
        .toList();
  }

  static Future<Map<String, dynamic>> details(int id) async {
    final uri = Uri.parse('$base/movie/$id').replace(
      queryParameters: {
        'api_key': apiKey,
        'language': 'en-US',
      },
    );

    final response = await http.get(uri).timeout(
      const Duration(seconds: 25),
    );

    if (response.statusCode != 200) {
      throw Exception('Could not load movie details.');
    }

    return jsonDecode(response.body) as Map<String, dynamic>;
  }
}

class FlixoraApp extends StatelessWidget {
  const FlixoraApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'FLIXORA',
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: bg,
        colorScheme: ColorScheme.fromSeed(
          seedColor: red,
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      home: const HomeScreen(),
    );
  }
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final PageController _sliderController = PageController();
  final TextEditingController _searchController = TextEditingController();

  Timer? _timer;
  Timer? _searchTimer;

  int _slide = 0;
  int _tab = 0;
  String _search = '';
  bool _searchLoading = false;
  String? _searchError;

  List<Movie> trending = [];
  List<Movie> popular = [];
  List<Movie> latest = [];
  List<Movie> topRated = [];
  List<Movie> searchResults = [];

  bool loading = true;
  String? homeError;

  final Set<int> _favourites = {};
  final Set<int> _saved = {};

  @override
  void initState() {
    super.initState();
    loadHome();

    _timer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (!mounted || _tab != 0 || trending.isEmpty) return;
      _slide = (_slide + 1) % trending.length;
      if (_sliderController.hasClients) {
        _sliderController.animateToPage(
          _slide,
          duration: const Duration(milliseconds: 600),
          curve: Curves.easeInOut,
        );
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _searchTimer?.cancel();
    _sliderController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> loadHome() async {
    setState(() {
      loading = true;
      homeError = null;
    });

    try {
      final results = await Future.wait([
        TmdbService.getMovies('trending/movie/week'),
        TmdbService.getMovies('movie/popular'),
        TmdbService.getMovies('movie/now_playing'),
        TmdbService.getMovies('movie/top_rated'),
      ]);

      if (!mounted) return;

      setState(() {
        trending = results[0];
        popular = results[1];
        latest = results[2];
        topRated = results[3];
        loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        loading = false;
        homeError = e.toString();
      });
    }
  }

  void searchMovies(String value) {
    _search = value;
    _searchTimer?.cancel();

    if (value.trim().isEmpty) {
      setState(() {
        searchResults = [];
        _searchError = null;
        _searchLoading = false;
      });
      return;
    }

    setState(() {
      _searchLoading = true;
      _searchError = null;
    });

    _searchTimer = Timer(const Duration(milliseconds: 600), () async {
      try {
        final results = await TmdbService.search(value.trim());
        if (!mounted || _search != value) return;
        setState(() {
          searchResults = results;
          _searchLoading = false;
        });
      } catch (e) {
        if (!mounted || _search != value) return;
        setState(() {
          _searchError = e.toString();
          _searchLoading = false;
        });
      }
    });
  }

  void toggleFavourite(Movie movie) {
    setState(() {
      if (!_favourites.add(movie.id)) {
        _favourites.remove(movie.id);
      }
    });
  }

  void toggleSaved(Movie movie) {
    setState(() {
      if (!_saved.add(movie.id)) {
        _saved.remove(movie.id);
      }
    });
  }

  void openMovie(Movie movie) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => MovieDetailsScreen(
          movie: movie,
          isFavourite: _favourites.contains(movie.id),
          isSaved: _saved.contains(movie.id),
          onFavourite: () => toggleFavourite(movie),
          onSave: () => toggleSaved(movie),
        ),
      ),
    ).then((_) {
      if (mounted) setState(() {});
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: IndexedStack(
          index: _tab,
          children: [
            _homePage(),
            _allPage(),
            _savedPage(),
            _profilePage(),
          ],
        ),
      ),
      bottomNavigationBar: NavigationBar(
        backgroundColor: panel,
        indicatorColor: red.withValues(alpha: 0.22),
        selectedIndex: _tab,
        onDestinationSelected: (value) {
          setState(() => _tab = value);
        },
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home, color: red),
            label: 'Home',
          ),
          NavigationDestination(
            icon: Icon(Icons.grid_view_outlined),
            selectedIcon: Icon(Icons.grid_view, color: red),
            label: 'All Movies',
          ),
          NavigationDestination(
            icon: Icon(Icons.bookmark_border),
            selectedIcon: Icon(Icons.bookmark, color: red),
            label: 'Saved',
          ),
          NavigationDestination(
            icon: Icon(Icons.person_outline),
            selectedIcon: Icon(Icons.person, color: red),
            label: 'Profile',
          ),
        ],
      ),
    );
  }

  Widget _header() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 12),
      child: Row(
        children: [
          const Text(
            'FLIXORA',
            style: TextStyle(
              color: red,
              fontSize: 30,
              fontWeight: FontWeight.w900,
              letterSpacing: 1.5,
            ),
          ),
          const Spacer(),
          IconButton(
            onPressed: () => _message('No new notifications'),
            icon: const Icon(Icons.notifications_none, size: 27),
          ),
          IconButton(
            onPressed: () => setState(() => _tab = 3),
            icon: const CircleAvatar(
              backgroundColor: panel,
              child: Icon(Icons.person_outline, color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }

  Widget _searchBox() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
      child: TextField(
        controller: _searchController,
        onChanged: searchMovies,
        decoration: InputDecoration(
          hintText: 'Search movies...',
          prefixIcon: const Icon(Icons.search),
          suffixIcon: _search.isNotEmpty
              ? IconButton(
                  onPressed: () {
                    _searchController.clear();
                    searchMovies('');
                  },
                  icon: const Icon(Icons.close),
                )
              : null,
          filled: true,
          fillColor: panel,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(20),
            borderSide: BorderSide.none,
          ),
        ),
      ),
    );
  }

  Widget _homePage() {
    if (loading) {
      return const Center(child: CircularProgressIndicator(color: red));
    }

    if (homeError != null) {
      return _errorView(homeError!, loadHome);
    }

    return CustomScrollView(
      physics: const BouncingScrollPhysics(),
      slivers: [
        SliverToBoxAdapter(child: _header()),
        SliverToBoxAdapter(child: _searchBox()),
        if (_search.isNotEmpty) ...[
          SliverToBoxAdapter(
            child: _sectionTitle('Search Results', 'TMDB'),
          ),
          if (_searchLoading)
            const SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.all(30),
                child: Center(child: CircularProgressIndicator(color: red)),
              ),
            )
          else if (_searchError != null)
            SliverToBoxAdapter(child: _errorView(_searchError!, () => searchMovies(_search)))
          else
            _movieGridSliver(searchResults),
        ] else ...[
          SliverToBoxAdapter(child: _sectionTitle('Featured', 'PREMIUM CINEMA')),
          SliverToBoxAdapter(child: _heroSlider()),
          SliverToBoxAdapter(child: _movieSection('Trending Now', trending)),
          SliverToBoxAdapter(child: _movieSection('Popular Movies', popular)),
          SliverToBoxAdapter(child: _movieSection('Now Playing', latest)),
          SliverToBoxAdapter(child: _movieSection('Top Rated', topRated)),
        ],
        const SliverToBoxAdapter(child: SizedBox(height: 25)),
      ],
    );
  }

  Widget _sectionTitle(String title, String subtitle) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 10, 20, 14),
      child: Row(
        children: [
          Text(title, style: const TextStyle(
            fontSize: 23,
            fontWeight: FontWeight.bold,
          )),
          const Spacer(),
          Text(subtitle, style: const TextStyle(
            color: Colors.white54,
            fontSize: 11,
            letterSpacing: 1.5,
            fontWeight: FontWeight.bold,
          )),
        ],
      ),
    );
  }

  Widget _heroSlider() {
    if (trending.isEmpty) return const SizedBox.shrink();

    return SizedBox(
      height: 390,
      child: PageView.builder(
        controller: _sliderController,
        itemCount: trending.length,
        onPageChanged: (index) => setState(() => _slide = index),
        itemBuilder: (context, index) {
          final movie = trending[index];
          return GestureDetector(
            onTap: () => openMovie(movie),
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 16),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(24),
                color: panel,
                image: movie.backdropUrl.isNotEmpty
                    ? DecorationImage(
                        image: NetworkImage(movie.backdropUrl),
                        fit: BoxFit.cover,
                        onError: (_, __) {},
                      )
                    : null,
              ),
              child: Container(
                padding: const EdgeInsets.all(22),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(24),
                  gradient: const LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Colors.transparent, Color(0xE6000000)],
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    const Text(
                      'TRENDING ON FLIXORA',
                      style: TextStyle(
                        color: Color(0xFFFF7777),
                        fontWeight: FontWeight.bold,
                        letterSpacing: 2,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(movie.title, maxLines: 2, overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 29,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text('${movie.year}  •  ⭐ ${movie.rating.toStringAsFixed(1)}'),
                    const SizedBox(height: 18),
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: red,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 22,
                          vertical: 14,
                        ),
                      ),
                      onPressed: () => openMovie(movie),
                      icon: const Icon(Icons.info_outline),
                      label: const Text('Explore Movie'),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: List.generate(trending.length > 8 ? 8 : trending.length, (i) {
                        return AnimatedContainer(
                          duration: const Duration(milliseconds: 250),
                          margin: const EdgeInsets.symmetric(horizontal: 3),
                          height: 6,
                          width: i == _slide % 8 ? 22 : 6,
                          decoration: BoxDecoration(
                            color: i == _slide % 8 ? red : Colors.white54,
                            borderRadius: BorderRadius.circular(10),
                          ),
                        );
                      }),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _movieSection(String title, List<Movie> list) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 14),
          child: Row(
            children: [
              Text(title, style: const TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
              )),
              const Spacer(),
              TextButton(
                onPressed: () => setState(() => _tab = 1),
                child: const Text('View all', style: TextStyle(color: Colors.white70)),
              ),
            ],
          ),
        ),
        SizedBox(
          height: 250,
          child: ListView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(),
            itemCount: list.length,
            itemBuilder: (context, index) => _movieCard(list[index]),
          ),
        ),
      ],
    );
  }

  Widget _movieCard(Movie movie) {
    return GestureDetector(
      onTap: () => openMovie(movie),
      child: Container(
        width: 145,
        margin: const EdgeInsets.symmetric(horizontal: 6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(15),
              child: Stack(
                children: [
                  movie.posterUrl.isEmpty
                      ? _posterFallback(145, 190)
                      : Image.network(
                          movie.posterUrl,
                          height: 190,
                          width: 145,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => _posterFallback(145, 190),
                        ),
                  Positioned(
                    top: 8,
                    right: 8,
                    child: GestureDetector(
                      onTap: () => toggleFavourite(movie),
                      child: CircleAvatar(
                        radius: 16,
                        backgroundColor: Colors.black54,
                        child: Icon(
                          _favourites.contains(movie.id)
                              ? Icons.favorite
                              : Icons.favorite_border,
                          color: red,
                          size: 18,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Text(movie.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            Text('${movie.year}  •  ⭐ ${movie.rating.toStringAsFixed(1)}',
              style: const TextStyle(color: Colors.white54, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }

  Widget _posterFallback(double width, double height) {
    return Container(
      height: height,
      width: width,
      color: panel,
      child: const Icon(Icons.movie_outlined, size: 45, color: Colors.white38),
    );
  }

  Widget _movieGridSliver(List<Movie> list) {
    if (list.isEmpty) {
      return const SliverToBoxAdapter(
        child: Padding(
          padding: EdgeInsets.all(40),
          child: Center(child: Text('No movies found')),
        ),
      );
    }

    return SliverPadding(
      padding: const EdgeInsets.symmetric(horizontal: 14),
      sliver: SliverGrid(
        delegate: SliverChildBuilderDelegate(
          (context, index) => _movieCard(list[index]),
          childCount: list.length,
        ),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          childAspectRatio: 0.64,
          crossAxisSpacing: 4,
          mainAxisSpacing: 10,
        ),
      ),
    );
  }

  Widget _allPage() {
    final all = <int, Movie>{};
    for (final list in [trending, popular, latest, topRated]) {
      for (final movie in list) {
        all[movie.id] = movie;
      }
    }
    final list = all.values.toList();

    return CustomScrollView(
      physics: const BouncingScrollPhysics(),
      slivers: [
        SliverToBoxAdapter(child: _header()),
        SliverToBoxAdapter(child: _searchBox()),
        SliverToBoxAdapter(child: _sectionTitle('All Movies', '${list.length} MOVIES')),
        _movieGridSliver(list),
        const SliverToBoxAdapter(child: SizedBox(height: 24)),
      ],
    );
  }

  Widget _savedPage() {
    final all = <int, Movie>{};
    for (final list in [trending, popular, latest, topRated]) {
      for (final movie in list) {
        all[movie.id] = movie;
      }
    }
    final list = all.values.where((m) => _saved.contains(m.id)).toList();

    return CustomScrollView(
      physics: const BouncingScrollPhysics(),
      slivers: [
        SliverToBoxAdapter(child: _header()),
        SliverToBoxAdapter(child: _sectionTitle('Saved Movies', '${list.length} SAVED')),
        if (list.isEmpty)
          const SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.all(45),
              child: Column(
                children: [
                  Icon(Icons.bookmark_border, size: 65, color: Colors.white38),
                  SizedBox(height: 15),
                  Text('No saved movies yet'),
                  SizedBox(height: 6),
                  Text('Open a movie and tap Save',
                    style: TextStyle(color: Colors.white54)),
                ],
              ),
            ),
          )
        else
          _movieGridSliver(list),
      ],
    );
  }

  Widget _profilePage() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const CircleAvatar(
            radius: 42,
            backgroundColor: panel,
            child: Icon(Icons.person, size: 48),
          ),
          const SizedBox(height: 16),
          const Text('FLIXORA USER',
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          const Text('Your cinematic experience',
            style: TextStyle(color: Colors.white54)),
          const SizedBox(height: 25),
          TextButton.icon(
            onPressed: () => _message('Account feature coming soon'),
            icon: const Icon(Icons.login),
            label: const Text('Sign in / Register'),
          ),
          const SizedBox(height: 20),
          const Padding(
            padding: EdgeInsets.all(20),
            child: Text(
              'This product uses the TMDB API but is not endorsed or certified by TMDB.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white38, fontSize: 11),
            ),
          ),
        ],
      ),
    );
  }

  Widget _errorView(String error, VoidCallback retry) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(25),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.wifi_off, size: 55, color: Colors.white54),
            const SizedBox(height: 16),
            const Text('Could not load movies',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            const SizedBox(height: 10),
            Text(error, textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white54)),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: retry,
              style: ElevatedButton.styleFrom(backgroundColor: red),
              child: const Text('Try Again'),
            ),
          ],
        ),
      ),
    );
  }

  void _message(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }
}

class MovieDetailsScreen extends StatefulWidget {
  final Movie movie;
  final bool isFavourite;
  final bool isSaved;
  final VoidCallback onFavourite;
  final VoidCallback onSave;

  const MovieDetailsScreen({
    super.key,
    required this.movie,
    required this.isFavourite,
    required this.isSaved,
    required this.onFavourite,
    required this.onSave,
  });

  @override
  State<MovieDetailsScreen> createState() => _MovieDetailsScreenState();
}

class _MovieDetailsScreenState extends State<MovieDetailsScreen> {
  late bool favourite;
  late bool saved;
  Map<String, dynamic>? extraDetails;
  String? detailsError;
  bool detailsLoading = true;

  @override
  void initState() {
    super.initState();
    favourite = widget.isFavourite;
    saved = widget.isSaved;
    loadDetails();
  }

  Future<void> loadDetails() async {
    try {
      final data = await TmdbService.details(widget.movie.id);
      if (!mounted) return;
      setState(() {
        extraDetails = data;
        detailsLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        detailsError = e.toString();
        detailsLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final movie = widget.movie;
    final genres = (extraDetails?['genres'] as List? ?? [])
        .map((g) => g['name'].toString())
        .join(', ');

    return Scaffold(
      body: CustomScrollView(
        physics: const BouncingScrollPhysics(),
        slivers: [
          SliverAppBar(
            expandedHeight: 300,
            pinned: true,
            backgroundColor: bg,
            flexibleSpace: FlexibleSpaceBar(
              background: movie.backdropUrl.isEmpty
                  ? Container(color: panel)
                  : Image.network(
                      movie.backdropUrl,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => Container(color: panel),
                    ),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(22),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(movie.title,
                    style: const TextStyle(fontSize: 29, fontWeight: FontWeight.w900)),
                  const SizedBox(height: 10),
                  Text(
                    '${movie.year}  •  ⭐ ${movie.rating.toStringAsFixed(1)}',
                    style: const TextStyle(color: Colors.white70),
                  ),
                  const SizedBox(height: 12),
                  if (detailsLoading)
                    const LinearProgressIndicator(color: red)
                  else if (detailsError == null && genres.isNotEmpty)
                    Text(genres, style: const TextStyle(color: Colors.white54)),
                  const SizedBox(height: 24),
                  const Text('Overview',
                    style: TextStyle(fontSize: 21, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 10),
                  Text(movie.overview,
                    style: const TextStyle(
                      color: Colors.white70,
                      height: 1.6,
                      fontSize: 15,
                    )),
                  if (extraDetails != null) ...[
                    const SizedBox(height: 22),
                    Text(
                      'Runtime: ${extraDetails!['runtime'] ?? 'N/A'} minutes',
                      style: const TextStyle(color: Colors.white70),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Release date: ${movie.releaseDate.isEmpty ? 'N/A' : movie.releaseDate}',
                      style: const TextStyle(color: Colors.white70),
                    ),
                  ],
                  const SizedBox(height: 28),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: red,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 15),
                      ),
                      onPressed: () {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('A licensed video source is needed for playback.'),
                          ),
                        );
                      },
                      icon: const Icon(Icons.play_arrow),
                      label: const Text('Watch'),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () {
                            widget.onFavourite();
                            setState(() => favourite = !favourite);
                          },
                          icon: Icon(favourite ? Icons.favorite : Icons.favorite_border),
                          label: Text(favourite ? 'Liked' : 'Favourite'),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () {
                            widget.onSave();
                            setState(() => saved = !saved);
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(saved
                                    ? 'Added to saved list'
                                    : 'Removed from saved list'),
                              ),
                            );
                          },
                          icon: Icon(saved ? Icons.bookmark : Icons.bookmark_border),
                          label: Text(saved ? 'Saved' : 'Save'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 30),
                  const Text(
                    'FLIXORA',
                    style: TextStyle(
                      color: red,
                      fontSize: 22,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 2,
                    ),
                  ),
                  const SizedBox(height: 30),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
