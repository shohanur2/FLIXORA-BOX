import 'package:flutter/material.dart';
import 'archive_service.dart';

class ArchiveScreen extends StatefulWidget {
  const ArchiveScreen({super.key});

  @override
  State<ArchiveScreen> createState() => _ArchiveScreenState();
}

class _ArchiveScreenState extends State<ArchiveScreen> {
  final TextEditingController searchController =
      TextEditingController(text: 'public domain');

  List<ArchiveMovie> movies = [];
  bool loading = false;
  String? error;

  @override
  void initState() {
    super.initState();
    searchMovies();
  }

  @override
  void dispose() {
    searchController.dispose();
    super.dispose();
  }

  Future<void> searchMovies() async {
    final query = searchController.text.trim();

    if (query.isEmpty) return;

    setState(() {
      loading = true;
      error = null;
    });

    try {
      final result = await ArchiveService.searchMovies(query);

      if (!mounted) return;

      setState(() {
        movies = result;
        loading = false;
      });
    } catch (e) {
      if (!mounted) return;

      setState(() {
        error = 'Could not load movies. Please try again.';
        loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF080808),
      appBar: AppBar(
        backgroundColor: const Color(0xFF080808),
        foregroundColor: const Color(0xFFD6AD45),
        title: const Text(
          'Free Movies',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: TextField(
              controller: searchController,
              style: const TextStyle(color: Colors.white),
              onSubmitted: (_) => searchMovies(),
              decoration: InputDecoration(
                hintText: 'Search free movies...',
                hintStyle: const TextStyle(color: Colors.grey),
                prefixIcon: const Icon(
                  Icons.search,
                  color: Color(0xFFD6AD45),
                ),
                suffixIcon: IconButton(
                  icon: const Icon(
                    Icons.arrow_forward,
                    color: Color(0xFFD6AD45),
                  ),
                  onPressed: searchMovies,
                ),
                filled: true,
                fillColor: const Color(0xFF191919),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              'Internet Archive • Public-domain and rights-cleared content only',
              style: TextStyle(
                color: Colors.white54,
                fontSize: 12,
              ),
            ),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: loading
                ? const Center(
                    child: CircularProgressIndicator(
                      color: Color(0xFFD6AD45),
                    ),
                  )
                : error != null
                    ? Center(
                        child: Text(
                          error!,
                          style: const TextStyle(color: Colors.white),
                        ),
                      )
                    : movies.isEmpty
                        ? const Center(
                            child: Text(
                              'No movies found',
                              style: TextStyle(color: Colors.white70),
                            ),
                          )
                        : ListView.builder(
                            itemCount: movies.length,
                            itemBuilder: (context, index) {
                              final movie = movies[index];

                              return Card(
                                color: const Color(0xFF191919),
                                margin: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 6,
                                ),
                                child: ListTile(
                                  leading: const Icon(
                                    Icons.movie,
                                    color: Color(0xFFD6AD45),
                                    size: 36,
                                  ),
                                  title: Text(
                                    movie.title,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  subtitle: Text(
                                    'Year: ${movie.year}\n'
                                    'Source: Internet Archive',
                                    style: const TextStyle(
                                      color: Colors.white60,
                                    ),
                                  ),
                                  isThreeLine: true,
                                ),
                              );
                            },
                          ),
          ),
        ],
      ),
    );
  }
}
