
import 'dart:async';
import 'package:flutter/material.dart';

void main() {
  runApp(const FlixoraApp());
}

const Color bg = Color(0xFF090A0F);
const Color panel = Color(0xFF191B25);
const Color red = Color(0xFFE50914);
const String imageBase = 'https://image.tmdb.org/t/p/';

class Movie {
  final String title;
  final String year;
  final String genre;
  final String overview;
  final String poster;
  final String backdrop;
  final double rating;

  const Movie({
    required this.title,
    required this.year,
    required this.genre,
    required this.overview,
    required this.poster,
    required this.backdrop,
    required this.rating,
  });
}

const List<Movie> movies = [
  Movie(
    title: 'Dune: Part Two',
    year: '2024',
    genre: 'Sci-Fi',
    rating: 8.5,
    poster: '/1pdfLvkbY9ohJlCjQH2CZjjYVvJ.jpg',
    backdrop: '/xOMo8BRK7PfcJv9JCnx7s5hj0PX.jpg',
    overview: 'Paul Atreides joins the Fremen on a journey of destiny and revenge across the desert planet Arrakis.',
  ),
  Movie(
    title: 'Deadpool & Wolverine',
    year: '2024',
    genre: 'Action',
    rating: 7.8,
    poster: '/8cdWjvZQUExUUTzyp4t6EDMubfO.jpg',
    backdrop: '/yDHYTfA3R0jFYba16jBB1ef8oIt.jpg',
    overview: 'Deadpool brings Wolverine into an adventure that changes everything.',
  ),
  Movie(
    title: 'Interstellar',
    year: '2014',
    genre: 'Sci-Fi',
    rating: 8.7,
    poster: '/gEU2QniE6E77NI6lCU6MxlNBvIx.jpg',
    backdrop: '/xJHokMbljvjADYdit5fK5VQsXEG.jpg',
    overview: 'A team of explorers travels beyond this galaxy to discover whether mankind has a future among the stars.',
  ),
  Movie(
    title: 'The Dark Knight',
    year: '2008',
    genre: 'Action',
    rating: 9.0,
    poster: '/qJ2tW6WMUDux911r6m7haRef0WH.jpg',
    backdrop: '/hkBaDkMWbLaf8B1lsWsKX7Ew3Xq.jpg',
    overview: 'Batman faces the Joker, a criminal mastermind who wants to plunge Gotham into chaos.',
  ),
  Movie(
    title: 'Spider-Man: No Way Home',
    year: '2021',
    genre: 'Adventure',
    rating: 8.1,
    poster: '/1g0dhYtq4irTY1GPXvft6k4YLjm.jpg',
    backdrop: '/14QbnygCuTO0vl7CAFmPf1fgZfV.jpg',
    overview: 'Peter Parker faces a multiverse adventure after his identity is revealed.',
  ),
  Movie(
    title: 'Avengers: Endgame',
    year: '2019',
    genre: 'Action',
    rating: 8.4,
    poster: '/or06FN3Dka5tukK1e9sl16pB3iy.jpg',
    backdrop: '/7RyHsO4yDXtBv1zUU3mTpHeQ0d5.jpg',
    overview: 'The Avengers assemble once more to reverse the damage caused by Thanos.',
  ),
  Movie(
    title: 'Joker',
    year: '2019',
    genre: 'Drama',
    rating: 8.2,
    poster: '/udDclJoHjfjb8Ekgsd4FDteOkCU.jpg',
    backdrop: '/n6bUvigpRFqSwmPp1m2YADdbRBc.jpg',
    overview: 'A troubled comedian slowly descends into madness in Gotham City.',
  ),
  Movie(
    title: 'The Batman',
    year: '2022',
    genre: 'Action',
    rating: 7.8,
    poster: '/74xTEgt7R36Fpooo50r9T25onhq.jpg',
    backdrop: '/b0PlSFdDwbyK0cf5RxwDpaOJQvQ.jpg',
    overview: 'Batman investigates corruption and a series of mysterious crimes in Gotham.',
  ),
];

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
  final PageController _sliderController =
      PageController(viewportFraction: 1);
  final TextEditingController _searchController = TextEditingController();

  Timer? _timer;
  int _slide = 0;
  int _tab = 0;
  String _category = 'All';
  String _search = '';

  final Set<String> _favourites = {};
  final Set<String> _saved = {};

  final List<String> categories = [
    'All', 'Action', 'Adventure', 'Sci-Fi', 'Drama', 'Comedy'
  ];

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (!mounted || _tab != 0) return;
      _slide = (_slide + 1) % movies.length;
      _sliderController.animateToPage(
        _slide,
        duration: const Duration(milliseconds: 600),
        curve: Curves.easeInOut,
      );
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _sliderController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  List<Movie> get filteredMovies {
    return movies.where((movie) {
      final matchesCategory =
          _category == 'All' || movie.genre == _category;
      final matchesSearch =
          movie.title.toLowerCase().contains(_search.toLowerCase());
      return matchesCategory && matchesSearch;
    }).toList();
  }

  void openMovie(Movie movie) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => MovieDetailsScreen(
          movie: movie,
          isFavourite: _favourites.contains(movie.title),
          isSaved: _saved.contains(movie.title),
          onFavourite: () {
            setState(() {
              if (!_favourites.add(movie.title)) {
                _favourites.remove(movie.title);
              }
            });
          },
          onSave: () {
            setState(() {
              if (!_saved.add(movie.title)) {
                _saved.remove(movie.title);
              }
            });
          },
        ),
      ),
    );
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
            onPressed: () => _showMessage('No new notifications'),
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
        onChanged: (value) => setState(() => _search = value),
        decoration: InputDecoration(
          hintText: 'Search movies, series...',
          prefixIcon: const Icon(Icons.search, color: Colors.white),
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
    return CustomScrollView(
      physics: const BouncingScrollPhysics(
        parent: AlwaysScrollableScrollPhysics(),
      ),
      slivers: [
        SliverToBoxAdapter(child: _header()),
        SliverToBoxAdapter(child: _searchBox()),
        if (_search.isEmpty) ...[
          SliverToBoxAdapter(child: _sectionTitle('Featured', 'PREMIUM CINEMA')),
          SliverToBoxAdapter(child: _heroSlider()),
          SliverToBoxAdapter(child: _categoryList()),
          SliverToBoxAdapter(
            child: _movieSection('Trending Now', movies.take(5).toList()),
          ),
          SliverToBoxAdapter(
            child: _movieSection('Latest Releases', movies.reversed.take(5).toList()),
          ),
          SliverToBoxAdapter(
            child: _movieSection('Top Rated', [...movies]..sort((a, b) => b.rating.compareTo(a.rating))),
          ),
          SliverToBoxAdapter(
            child: _movieSection('Action Movies', movies.where((m) => m.genre == 'Action').toList()),
          ),
        ],
        if (_search.isNotEmpty)
          _movieGridSliver(filteredMovies),
        const SliverToBoxAdapter(child: SizedBox(height: 24)),
      ],
    );
  }

  Widget _sectionTitle(String title, String subtitle) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 10, 20, 14),
      child: Row(
        children: [
          Text(title,
              style: const TextStyle(fontSize: 23, fontWeight: FontWeight.bold)),
          const Spacer(),
          Text(subtitle,
              style: const TextStyle(
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
    return SizedBox(
      height: 390,
      child: PageView.builder(
        controller: _sliderController,
        itemCount: movies.length,
        onPageChanged: (index) => setState(() => _slide = index),
        itemBuilder: (context, index) {
          final movie = movies[index];
          return GestureDetector(
            onTap: () => openMovie(movie),
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 16),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(24),
                image: DecorationImage(
                  image: NetworkImage(imageBase + 'w780' + movie.backdrop),
                  fit: BoxFit.cover,
                  onError: (_, __) {},
                ),
              ),
              child: Container(
                padding: const EdgeInsets.all(22),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(24),
                  gradient: const LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.transparent,
                      Color(0xE6000000),
                    ],
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    const Text(
                      'FLIXORA ORIGINAL',
                      style: TextStyle(
                        color: Color(0xFFFF7777),
                        fontWeight: FontWeight.bold,
                        letterSpacing: 2,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      movie.title,
                      style: const TextStyle(
                        fontSize: 29,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text('${movie.year}  •  ${movie.genre}  •  ⭐ ${movie.rating}'),
                    const SizedBox(height: 18),
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: red,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 22, vertical: 14),
                      ),
                      onPressed: () => openMovie(movie),
                      icon: const Icon(Icons.play_arrow),
                      label: const Text('Explore Movie'),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: List.generate(movies.length, (i) {
                        return AnimatedContainer(
                          duration: const Duration(milliseconds: 250),
                          margin: const EdgeInsets.symmetric(horizontal: 3),
                          height: 6,
                          width: i == _slide ? 22 : 6,
                          decoration: BoxDecoration(
                            color: i == _slide ? red : Colors.white54,
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

  Widget _categoryList() {
    return SizedBox(
      height: 76,
      child: ListView.builder(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        scrollDirection: Axis.horizontal,
        itemCount: categories.length,
        itemBuilder: (context, index) {
          final item = categories[index];
          final selected = item == _category;
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 5),
            child: ChoiceChip(
              label: Text(item),
              selected: selected,
              selectedColor: red,
              backgroundColor: panel,
              onSelected: (_) {
                setState(() {
                  _category = item;
                  _tab = 1;
                });
              },
              labelStyle: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
              side: BorderSide.none,
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
              Text(title,
                  style: const TextStyle(
                      fontSize: 22, fontWeight: FontWeight.bold)),
              const Spacer(),
              TextButton(
                onPressed: () {
                  setState(() {
                    _category = 'All';
                    _tab = 1;
                  });
                },
                child: const Text('View all',
                    style: TextStyle(color: Colors.white70)),
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
            itemBuilder: (context, index) {
              return _movieCard(list[index]);
            },
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
                  Image.network(
                    imageBase + 'w342' + movie.poster,
                    height: 190,
                    width: 145,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => _posterFallback(145, 190),
                  ),
                  Positioned(
                    top: 8,
                    right: 8,
                    child: GestureDetector(
                      onTap: () {
                        setState(() {
                          if (!_favourites.add(movie.title)) {
                            _favourites.remove(movie.title);
                          }
                        });
                      },
                      child: CircleAvatar(
                        radius: 16,
                        backgroundColor: Colors.black54,
                        child: Icon(
                          _favourites.contains(movie.title)
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
                style: const TextStyle(fontWeight: FontWeight.bold)),
            Text('${movie.year}  •  ${movie.genre}',
                style: const TextStyle(color: Colors.white54, fontSize: 12)),
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
    final list = filteredMovies;
    return CustomScrollView(
      physics: const BouncingScrollPhysics(),
      slivers: [
        SliverToBoxAdapter(child: _header()),
        SliverToBoxAdapter(child: _searchBox()),
        SliverToBoxAdapter(
          child: _sectionTitle('All Movies', '${list.length} MOVIES'),
        ),
        SliverToBoxAdapter(child: _categoryList()),
        _movieGridSliver(list),
        const SliverToBoxAdapter(child: SizedBox(height: 24)),
      ],
    );
  }

  Widget _savedPage() {
    final list = movies.where((m) => _saved.contains(m.title)).toList();
    return CustomScrollView(
      physics: const BouncingScrollPhysics(),
      slivers: [
        SliverToBoxAdapter(child: _header()),
        SliverToBoxAdapter(
          child: _sectionTitle('Saved Movies', '${list.length} SAVED'),
        ),
        if (list.isEmpty)
          const SliverToBoxAdapter(
            child: Center(
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
            onPressed: () => _showMessage('Account feature coming soon'),
            icon: const Icon(Icons.login),
            label: const Text('Sign in / Register'),
          ),
        ],
      ),
    );
  }

  void _showMessage(String message) {
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

  @override
  void initState() {
    super.initState();
    favourite = widget.isFavourite;
    saved = widget.isSaved;
  }

  @override
  Widget build(BuildContext context) {
    final movie = widget.movie;

    return Scaffold(
      body: CustomScrollView(
        physics: const BouncingScrollPhysics(),
        slivers: [
          SliverAppBar(
            expandedHeight: 300,
            pinned: true,
            backgroundColor: bg,
            flexibleSpace: FlexibleSpaceBar(
              background: Image.network(
                imageBase + 'w780' + movie.backdrop,
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
                      style: const TextStyle(
                          fontSize: 29, fontWeight: FontWeight.w900)),
                  const SizedBox(height: 10),
                  Text('${movie.year}  •  ${movie.genre}  •  ⭐ ${movie.rating}',
                      style: const TextStyle(color: Colors.white70)),
                  const SizedBox(height: 24),
                  const Text('Overview',
                      style:
                          TextStyle(fontSize: 21, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 10),
                  Text(movie.overview,
                      style: const TextStyle(
                          color: Colors.white70, height: 1.6, fontSize: 15)),
                  const SizedBox(height: 28),
                  Row(
                    children: [
                      Expanded(
                        child: ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: red,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 15),
                          ),
                          onPressed: () {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text(
                                  'A licensed video source is needed for playback.',
                                ),
                              ),
                            );
                          },
                          icon: const Icon(Icons.play_arrow),
                          label: const Text('Watch'),
                        ),
                      ),
                    ],
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
                          icon: Icon(favourite
                              ? Icons.favorite
                              : Icons.favorite_border),
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
                                    ? 'Removed from saved list'
                                    : 'Added to saved list'),
                              ),
                            );
                          },
                          icon: Icon(saved
                              ? Icons.bookmark
                              : Icons.bookmark_border),
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
