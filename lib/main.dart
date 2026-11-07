
import 'package:flutter/material.dart';

void main() {
  runApp(const FlixoraApp());
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
        scaffoldBackgroundColor: const Color(0xFF090B10),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFFE50914),
          surface: Color(0xFF151922),
        ),
        useMaterial3: true,
      ),
      home: const HomeScreen(),
    );
  }
}

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  final List<String> categories = const [
    'All', 'Action', 'Adventure', 'Comedy', 'Drama', 'Anime'
  ];

  final List<Map<String, String>> movies = const [
    {'title': 'The Dark Knight', 'year': '2008', 'genre': 'Action'},
    {'title': 'Interstellar', 'year': '2014', 'genre': 'Sci-Fi'},
    {'title': 'Inception', 'year': '2010', 'genre': 'Thriller'},
    {'title': 'Avengers', 'year': '2019', 'genre': 'Adventure'},
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: CustomScrollView(
          slivers: [
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 18),
                child: Row(
                  children: [
                    const Text(
                      'FLIXORA',
                      style: TextStyle(
                        color: Color(0xFFE50914),
                        fontSize: 27,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 2,
                      ),
                    ),
                    const Spacer(),
                    IconButton(
                      onPressed: () {},
                      icon: const Icon(Icons.notifications_none),
                    ),
                    CircleAvatar(
                      backgroundColor: Colors.white12,
                      child: const Icon(Icons.person_outline),
                    ),
                  ],
                ),
              ),
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: TextField(
                  decoration: InputDecoration(
                    hintText: 'Search movies, series...',
                    prefixIcon: const Icon(Icons.search),
                    filled: true,
                    fillColor: const Color(0xFF171B24),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
              ),
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 28, 20, 14),
                child: Row(
                  children: [
                    const Text(
                      'Featured',
                      style: TextStyle(
                        fontSize: 21,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      'PREMIUM CINEMA',
                      style: TextStyle(
                        color: Colors.grey.shade500,
                        fontSize: 10,
                        letterSpacing: 1.5,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Container(
                  height: 220,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(20),
                    gradient: const LinearGradient(
                      colors: [
                        Color(0xFF57131B),
                        Color(0xFF211522),
                        Color(0xFF10131C),
                      ],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                  ),
                  child: Stack(
                    children: [
                      Positioned(
                        right: 12,
                        top: 12,
                        child: Icon(
                          Icons.movie_creation_outlined,
                          size: 105,
                          color: Colors.white.withOpacity(0.08),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.all(20),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            const Text(
                              'FLIXORA ORIGINAL',
                              style: TextStyle(
                                color: Color(0xFFFF646B),
                                fontSize: 11,
                                letterSpacing: 2,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 8),
                            const Text(
                              'Unlimited\nEntertainment.',
                              style: TextStyle(
                                fontSize: 27,
                                height: 1.15,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                            const SizedBox(height: 14),
                            ElevatedButton.icon(
                              onPressed: () {},
                              icon: const Icon(Icons.play_arrow),
                              label: const Text('Explore Movies'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFFE50914),
                                foregroundColor: Colors.white,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            SliverToBoxAdapter(
              child: SizedBox(
                height: 65,
                child: ListView.separated(
                  padding: const EdgeInsets.fromLTRB(20, 20, 20, 10),
                  scrollDirection: Axis.horizontal,
                  itemCount: categories.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 10),
                  itemBuilder: (context, index) {
                    final selected = index == 0;
                    return Container(
                      padding: const EdgeInsets.symmetric(horizontal: 18),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: selected
                            ? const Color(0xFFE50914)
                            : const Color(0xFF171B24),
                        borderRadius: BorderRadius.circular(30),
                      ),
                      child: Text(
                        categories[index],
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 14),
                child: Row(
                  children: [
                    const Text(
                      'Trending Now',
                      style: TextStyle(
                        fontSize: 21,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      'View all',
                      style: TextStyle(color: Colors.grey.shade400),
                    ),
                  ],
                ),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              sliver: SliverGrid(
                delegate: SliverChildBuilderDelegate(
                  (context, index) {
                    final movie = movies[index];
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Container(
                            width: double.infinity,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(14),
                              gradient: LinearGradient(
                                colors: [
                                  Colors.primaries[index * 3].withOpacity(0.65),
                                  const Color(0xFF171B24),
                                ],
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                              ),
                            ),
                            child: const Center(
                              child: Icon(
                                Icons.movie_outlined,
                                size: 48,
                                color: Colors.white54,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          movie['title']!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          '${movie['year']} • ${movie['genre']}',
                          style: TextStyle(
                            color: Colors.grey.shade500,
                            fontSize: 11,
                          ),
                        ),
                      ],
                    );
                  },
                  childCount: movies.length,
                ),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  mainAxisSpacing: 20,
                  crossAxisSpacing: 14,
                  childAspectRatio: 0.70,
                ),
              ),
            ),
            const SliverToBoxAdapter(
              child: SizedBox(height: 35),
            ),
          ],
        ),
      ),
    );
  }
}
