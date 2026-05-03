import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:image_picker/image_picker.dart';
import 'package:google_fonts/google_fonts.dart';
import 'dart:typed_data';

class ImageListScreen extends StatefulWidget {
  const ImageListScreen({super.key});

  @override
  State<ImageListScreen> createState() => _ImageListScreenState();
}

class _ImageListScreenState extends State<ImageListScreen> {
  final SupabaseClient supabase = Supabase.instance.client;
  
  // Listas para armazenar todas as imagens e as imagens filtradas pela pesquisa
  List<Map<String, dynamic>> _images = [];
  List<Map<String, dynamic>> _filteredImages = [];
  bool _isLoading = true;
  
  // Controller para o campo de busca
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _fetchImages(); // Busca inicial das imagens
    _searchController.addListener(_filterImages); // Listener para busca em tempo real
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  // Busca as imagens no banco de dados do Supabase
  Future<void> _fetchImages() async {
    setState(() => _isLoading = true);
    try {
      final response = await supabase
          .from('images')
          .select()
          .order('created_at', ascending: false);
      
      setState(() {
        _images = List<Map<String, dynamic>>.from(response);
        _filteredImages = _images;
        _isLoading = false;
      });
    } catch (e) {
      debugPrint('Erro ao buscar imagens: $e');
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro ao carregar imagens: $e')),
        );
      }
    }
  }

  // Filtra a lista de imagens baseado no texto digitado no campo de busca
  void _filterImages() {
    final query = _searchController.text.toLowerCase();
    setState(() {
      _filteredImages = _images.where((img) {
        final name = img['name']?.toString().toLowerCase() ?? '';
        return name.contains(query);
      }).toList();
    });
  }

  // Abre o modal para adicionar uma nova imagem
  Future<void> _addImage() async {
    final nameController = TextEditingController();
    XFile? selectedImage;
    Uint8List? imageBytes;
    final ImagePicker picker = ImagePicker();

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) => Container(
          decoration: const BoxDecoration(
            color: Color(0xFF1E1E2E),
            borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
          ),
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).viewInsets.bottom + 20,
            top: 20,
            left: 20,
            right: 20,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Barra indicadora de "drag" do modal
              Center(
                child: Container(
                  width: 50,
                  height: 5,
                  decoration: BoxDecoration(
                    color: Colors.grey[600],
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
              const SizedBox(height: 25),
              Text(
                'Adicionar nova imagem',
                style: GoogleFonts.outfit(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 25),
              TextField(
                controller: nameController,
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  hintText: 'Nome da imagem',
                  hintStyle: TextStyle(color: Colors.grey[400]),
                  filled: true,
                  fillColor: const Color(0xFF2D2D3F),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(15),
                    borderSide: BorderSide.none,
                  ),
                  prefixIcon: Icon(Icons.label_outline, color: Colors.grey[400]),
                ),
              ),
              const SizedBox(height: 20),
              // Área de seleção de imagem
              GestureDetector(
                onTap: () async {
                  final XFile? image = await picker.pickImage(source: ImageSource.gallery);
                  if (image != null) {
                    final bytes = await image.readAsBytes();
                    setModalState(() {
                      selectedImage = image;
                      imageBytes = bytes;
                    });
                  }
                },
                child: Container(
                  height: 150,
                  decoration: BoxDecoration(
                    color: const Color(0xFF2D2D3F),
                    borderRadius: BorderRadius.circular(15),
                    border: Border.all(
                      color: imageBytes != null ? Colors.blueAccent : Colors.grey[700]!,
                      width: 2,
                    ),
                  ),
                  child: imageBytes != null
                      ? ClipRRect(
                          borderRadius: BorderRadius.circular(13),
                          // Exibe o preview da imagem selecionada em memória
                          child: Image.memory(imageBytes!, fit: BoxFit.cover),
                        )
                      : Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.add_photo_alternate_outlined, size: 40, color: Colors.grey[400]),
                            const SizedBox(height: 10),
                            Text(
                              'Toque para selecionar imagem',
                              style: TextStyle(color: Colors.grey[400]),
                            ),
                          ],
                        ),
                ),
              ),
              const SizedBox(height: 30),
              ElevatedButton(
                onPressed: () async {
                  if (nameController.text.isEmpty || selectedImage == null || imageBytes == null) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Por favor, preencha o nome e selecione uma imagem')),
                    );
                    return;
                  }

                  Navigator.pop(context); // Fecha o modal
                  await _uploadAndSave(nameController.text, selectedImage!, imageBytes!);
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blueAccent,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 15),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(15),
                  ),
                ),
                child: Text(
                  'Salvar imagem',
                  style: GoogleFonts.outfit(fontSize: 18, fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // Faz o upload da imagem para o Storage e salva o registro no banco de dados
  Future<void> _uploadAndSave(String name, XFile imageFile, Uint8List bytes) async {
    setState(() => _isLoading = true);
    try {
      final String fileName = '${DateTime.now().millisecondsSinceEpoch}.jpg';
      final String path = 'uploads/$fileName';

      // Upload para o Storage do Supabase (bucket 'images')
      await supabase.storage.from('images').uploadBinary(path, bytes);

      // Obtém a URL pública da imagem recém enviada
      final String publicUrl = supabase.storage.from('images').getPublicUrl(path);

      // Insere o registro na tabela 'images'
      await supabase.from('images').insert({
        'name': name,
        'url': publicUrl,
      });

      await _fetchImages(); // Atualiza a lista após salvar
    } catch (e) {
      debugPrint('Erro no upload/salvamento: $e');
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro ao salvar imagem: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF13131F),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Minhas imagens',
                style: GoogleFonts.outfit(
                  fontSize: 32,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 20),
              // Campo de busca
              TextField(
                controller: _searchController,
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  hintText: 'Pesquisar imagens...',
                  hintStyle: TextStyle(color: Colors.grey[500]),
                  prefixIcon: Icon(Icons.search, color: Colors.grey[500]),
                  filled: true,
                  fillColor: const Color(0xFF1E1E2E),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(20),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
              const SizedBox(height: 25),
              // Grid de imagens com 3 colunas
              Expanded(
                child: _isLoading
                    ? const Center(child: CircularProgressIndicator(color: Colors.blueAccent))
                    : GridView.builder(
                        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 3,
                          crossAxisSpacing: 15,
                          mainAxisSpacing: 15,
                          childAspectRatio: 1,
                        ),
                        // O itemCount é a lista filtrada + o botão de adicionar no final
                        itemCount: _filteredImages.length + 1,
                        itemBuilder: (context, index) {
                          if (index == _filteredImages.length) {
                            return _buildAddButton();
                          }
                          final image = _filteredImages[index];
                          return _buildImageCard(image);
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // Constrói o card individual de cada imagem na grid
  Widget _buildImageCard(Map<String, dynamic> image) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(15),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.3),
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(15),
        child: Stack(
          fit: StackFit.expand,
          children: [
            // Imagem carregada da rede via Supabase Public URL
            Image.network(
              image['url'],
              fit: BoxFit.cover,
              errorBuilder: (context, error, stackTrace) => Container(
                color: const Color(0xFF2D2D3F),
                child: const Icon(Icons.broken_image, color: Colors.grey),
              ),
              loadingBuilder: (context, child, loadingProgress) {
                if (loadingProgress == null) return child;
                return Container(
                  color: const Color(0xFF2D2D3F),
                  child: const Center(
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.blueAccent),
                  ),
                );
              },
            ),
            // Overlay com o nome da imagem no rodapé
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.bottomCenter,
                    end: Alignment.topCenter,
                    colors: [
                      Colors.black.withValues(alpha: 0.8),
                      Colors.transparent,
                    ],
                  ),
                ),
                child: Text(
                  image['name'] ?? '',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Constrói o botão '+' posicionado no final da grid
  Widget _buildAddButton() {
    return GestureDetector(
      onTap: _addImage,
      child: Container(
        decoration: BoxDecoration(
          color: const Color(0xFF1E1E2E),
          borderRadius: BorderRadius.circular(15),
          border: Border.all(
            color: Colors.blueAccent.withValues(alpha: 0.5),
            width: 2,
            style: BorderStyle.solid,
          ),
        ),
        child: const Center(
          child: Icon(
            Icons.add_rounded,
            color: Colors.blueAccent,
            size: 40,
          ),
        ),
      ),
    );
  }
}
