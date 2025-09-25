import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'cache_ia_service.dart';
import 'ia_service.dart';

class QuizHelperService {
  /// Gera pergunta inteligente usando cache quando possível
  static Future<Map<String, dynamic>?> gerarPerguntaInteligente({
    required String unidade,
    required String ano,
    required String tipoQuiz,
    required String dificuldade,
  }) async {
    try {
      // Primeira tentativa: buscar no cache
      var pergunta = await CacheIAService.obterPergunta(
        unidade: unidade,
        ano: ano,
        tipoQuiz: tipoQuiz,
        dificuldade: dificuldade,
      );

      // Se encontrou no cache, retorna
      if (pergunta != null) {
        return pergunta;
      }

      // Se não tem no cache, gera nova pergunta
      pergunta = await _gerarPerguntaViaIA(
        unidade: unidade,
        ano: ano,
        tipoQuiz: tipoQuiz,
        dificuldade: dificuldade,
      );

      // Se conseguiu gerar via IA, adiciona indicador de fonte
      if (pergunta != null) {
        pergunta['fonte_ia'] = 'gemini'; // ou 'ollama' baseado na configuração
      }

      return pergunta;
    } catch (e) {
      if (kDebugMode) {
        print('❌ Erro ao gerar pergunta inteligente: $e');
      }
      return null;
    }
  }

  /// Gera pergunta diretamente via IA
  static Future<Map<String, dynamic>?> _gerarPerguntaViaIA({
    required String unidade,
    required String ano,
    required String tipoQuiz,
    required String dificuldade,
  }) async {
    try {
      if (kDebugMode) {
        print(
            '🤖 Iniciando geração via IA: $tipoQuiz - $unidade - $dificuldade');
      }

      // Cria serviço AI baseado nas preferências do usuário
      final prefs = await SharedPreferences.getInstance();
      final selectedAI = prefs.getString('selected_ai') ?? 'gemini';
      final apiKey = prefs.getString('gemini_api_key');
      final modeloOllama = prefs.getString('modelo_ollama') ?? 'llama2';

      if (kDebugMode) {
        print('🔧 IA selecionada: $selectedAI');
        print('🔑 API Key definida: ${apiKey != null && apiKey.isNotEmpty}');
      }

      AIService aiService;
      if (selectedAI == 'gemini') {
        if (apiKey == null || apiKey.isEmpty) {
          if (kDebugMode) {
            print('❌ API Key do Gemini não configurada');
          }
          return null;
        }
        aiService = GeminiService(apiKey: apiKey);
      } else {
        aiService = OllamaService(defaultModel: modeloOllama);
      }

      final tutorService = MathTutorService(aiService: aiService);

      String prompt = _criarPrompt(
        unidade: unidade,
        ano: ano,
        tipoQuiz: tipoQuiz,
        dificuldade: dificuldade,
      );

      if (kDebugMode) {
        final promptPreview =
            prompt.length > 100 ? '${prompt.substring(0, 100)}...' : prompt;
        print('📝 Prompt gerado: $promptPreview');
      }

      final response = await tutorService.aiService.generate(prompt);

      if (kDebugMode) {
        final responsePreview = response.length > 200
            ? '${response.substring(0, 200)}...'
            : response;
        print('🤖 Resposta da IA: $responsePreview');
      }

      final pergunta = _processarRespostaIA(response, tipoQuiz, dificuldade);

      if (pergunta != null && kDebugMode) {
        final perguntaText = pergunta['pergunta']?.toString() ?? '';
        final perguntaPreview = perguntaText.length > 50
            ? '${perguntaText.substring(0, 50)}...'
            : perguntaText;
        print('✅ Pergunta processada com sucesso: $perguntaPreview');
      } else if (kDebugMode) {
        print('❌ Falha ao processar resposta da IA');
      }

      return pergunta;
    } catch (e) {
      if (kDebugMode) {
        print('❌ Erro ao gerar pergunta via IA: $e');
      }
      return null;
    }
  }

  /// Cria prompt específico para cada tipo de quiz
  static String _criarPrompt({
    required String unidade,
    required String ano,
    required String tipoQuiz,
    required String dificuldade,
  }) {
    // Descrições detalhadas de dificuldade baseadas no ano escolar
    String descricaoDificuldade;
    switch (dificuldade.toLowerCase()) {
      case 'fácil':
        descricaoDificuldade = '''
- Conceitos básicos e fundamentais da unidade
- Cálculos simples e diretos
- Aplicações imediatas e óbvias
- Adequado para revisão ou introdução ao tópico
- Exemplos: operações básicas, reconhecimento de padrões simples''';
        break;
      case 'médio':
        descricaoDificuldade = '''
- Aplicação prática dos conceitos
- Problemas com 1-2 passos de raciocínio
- Interpretação de situações do dia a dia
- Combinação de conceitos básicos
- Exemplos: resolução de problemas contextualizados, cálculos intermediários''';
        break;
      case 'difícil':
        descricaoDificuldade = '''
- Raciocínio avançado e análise crítica
- Problemas complexos com múltiplos passos
- Aplicações não óbvias e desafiadoras
- Integração de múltiplos conceitos
- Exemplos: problemas de otimização, situações complexas que exigem estratégia''';
        break;
      default:
        descricaoDificuldade = '''
- Nível adequado ao progresso do estudante
- Equilibra desafio e acessibilidade''';
    }

    final basePrompt = '''
Contexto: Estou criando uma pergunta de matemática para um estudante do $ano sobre a unidade temática "$unidade" da BNCC.
Nível de dificuldade: $dificuldade

INSTRUÇÕES ESPECÍFICAS DE DIFICULDADE:
$descricaoDificuldade

IMPORTANTE: Garanta que a pergunta seja ORIGINAL e NÃO REPETITIVA. Evite fórmulas, conceitos ou contextos já usados anteriormente. Varie os exemplos e situações apresentadas.

''';

    switch (tipoQuiz.toLowerCase()) {
      case 'multipla_escolha':
        return '''${basePrompt}Crie uma pergunta de múltipla escolha seguindo EXATAMENTE este formato:

PERGUNTA: [pergunta clara e objetiva]
A) [opção A]
B) [opção B] 
C) [opção C]
D) [opção D]
RESPOSTA_CORRETA: [letra da resposta correta]
EXPLICACAO: [explicação breve e didática]

Características:
- Pergunta clara e contextualizada
- 4 alternativas plausíveis, incluindo distratores realistas
- Apenas uma resposta correta
- Explicação educativa que explica o conceito
- Adequada ao $ano e unidade "$unidade"
- Nível de dificuldade $dificuldade conforme especificado acima
''';

      case 'verdadeiro_falso':
        return '''${basePrompt}Crie uma pergunta de verdadeiro ou falso seguindo EXATAMENTE este formato:

PERGUNTA: [afirmação clara para avaliar]
RESPOSTA_CORRETA: [Verdadeiro ou Falso]
EXPLICACAO: [explicação breve do porquê a afirmação é verdadeira ou falsa]

Características:
- Afirmação clara e não ambígua
- Adequada ao $ano e unidade "$unidade"
- Explicação didática que esclarece o conceito
- Inclua elementos que testem compreensão real, não apenas memorização
- Nível de dificuldade $dificuldade conforme especificado acima
''';

      case 'complete_frase':
        return '''${basePrompt}Crie uma pergunta de completar frase seguindo EXATAMENTE este formato:

PERGUNTA: [frase com lacuna marcada por ____]
RESPOSTA_CORRETA: [palavra ou expressão que completa corretamente]
EXPLICACAO: [explicação do conceito]

Características:
- Frase clara com lacuna bem definida
- Resposta específica e única
- Adequada ao $ano e unidade "$unidade"
- Explicação didática que explica o conceito
- Foque em termos técnicos ou conceitos chave da unidade
- Nível de dificuldade $dificuldade conforme especificado acima
''';

      default:
        return '${basePrompt}Crie uma pergunta de matemática adequada ao contexto.';
    }
  }

  /// Processa a resposta da IA e extrai os componentes
  static Map<String, dynamic>? _processarRespostaIA(
      String response, String tipoQuiz, String dificuldade) {
    try {
      final linhas = response
          .split('\n')
          .where((linha) => linha.trim().isNotEmpty)
          .toList();

      switch (tipoQuiz.toLowerCase()) {
        case 'multipla_escolha':
          return _processarMultiplaEscolha(linhas, dificuldade);
        case 'verdadeiro_falso':
          return _processarVerdadeiroFalso(linhas, dificuldade);
        case 'complete_frase':
          return _processarCompleteFrase(linhas, dificuldade);
        default:
          return null;
      }
    } catch (e) {
      if (kDebugMode) {
        print('❌ Erro ao processar resposta da IA: $e');
      }
      return null;
    }
  }

  /// Processa resposta de múltipla escolha
  static Map<String, dynamic>? _processarMultiplaEscolha(
      List<String> linhas, String dificuldade) {
    String? pergunta;
    List<String> opcoes = [];
    String? respostaCorreta;
    String? explicacao;

    for (String linha in linhas) {
      linha = linha.trim();

      if (linha.startsWith('PERGUNTA:')) {
        pergunta = linha.substring(9).trim();
      } else if (linha.startsWith('A)') ||
          linha.startsWith('B)') ||
          linha.startsWith('C)') ||
          linha.startsWith('D)')) {
        opcoes.add(linha.substring(2).trim());
      } else if (linha.startsWith('RESPOSTA_CORRETA:')) {
        respostaCorreta = linha.substring(17).trim();
      } else if (linha.startsWith('EXPLICACAO:')) {
        explicacao = linha.substring(11).trim();
      }
    }

    if (pergunta != null && opcoes.length == 4 && respostaCorreta != null) {
      return {
        'pergunta': pergunta,
        'opcoes': opcoes,
        'resposta_correta': respostaCorreta,
        'explicacao': explicacao,
        'dificuldade': dificuldade,
      };
    }

    return null;
  }

  /// Processa resposta de verdadeiro/falso
  static Map<String, dynamic>? _processarVerdadeiroFalso(
      List<String> linhas, String dificuldade) {
    String? pergunta;
    String? respostaCorreta;
    String? explicacao;

    for (String linha in linhas) {
      linha = linha.trim();

      if (linha.startsWith('PERGUNTA:')) {
        pergunta = linha.substring(9).trim();
      } else if (linha.startsWith('RESPOSTA_CORRETA:')) {
        respostaCorreta = linha.substring(17).trim();
      } else if (linha.startsWith('EXPLICACAO:')) {
        explicacao = linha.substring(11).trim();
      }
    }

    if (pergunta != null && respostaCorreta != null) {
      return {
        'pergunta': pergunta,
        'resposta_correta': respostaCorreta,
        'explicacao': explicacao,
        'dificuldade': dificuldade,
      };
    }

    return null;
  }

  /// Processa resposta de completar frase
  static Map<String, dynamic>? _processarCompleteFrase(
      List<String> linhas, String dificuldade) {
    String? pergunta;
    String? respostaCorreta;
    String? explicacao;

    for (String linha in linhas) {
      linha = linha.trim();

      if (linha.startsWith('PERGUNTA:')) {
        pergunta = linha.substring(9).trim();
      } else if (linha.startsWith('RESPOSTA_CORRETA:')) {
        respostaCorreta = linha.substring(17).trim();
      } else if (linha.startsWith('EXPLICACAO:')) {
        explicacao = linha.substring(11).trim();
      }
    }

    if (pergunta != null && respostaCorreta != null) {
      return {
        'pergunta': pergunta,
        'resposta_correta': respostaCorreta,
        'explicacao': explicacao,
        'dificuldade': dificuldade,
      };
    }

    return null;
  }

  /// Pré-carrega cache para melhorar performance
  static Future<void> preCarregarCacheModulo(String unidade, String ano) async {
    await CacheIAService.preCarregarCache(
      unidade: unidade,
      ano: ano,
      quantidadePorTipo: 5,
    );
  }

  /// Obtém estatísticas de uso do cache
  static Future<Map<String, dynamic>> obterEstatisticasCache() async {
    return await CacheIAService.obterEstatisticasCache();
  }

  /// Limpa cache se necessário
  static Future<void> limparCacheSeNecessario() async {
    final stats = await CacheIAService.obterEstatisticasCache();
    final totalPerguntas = stats['total_perguntas_cache'] ?? 0;

    // Se o cache está muito grande (mais de 1000 perguntas), otimiza
    if (totalPerguntas > 1000) {
      await CacheIAService.otimizarCache();
    }
  }
}
