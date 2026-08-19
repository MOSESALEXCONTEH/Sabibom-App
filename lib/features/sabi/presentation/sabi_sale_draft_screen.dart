import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router.dart';
import '../../../core/formatting/currency_formatter.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/app_status_views.dart';
import '../../dashboard/application/dashboard_providers.dart';
import '../../sales/application/sale_cart_controller.dart';
import '../../sales/application/sales_providers.dart' as sales;
import '../../sales/domain/quantity_input.dart';
import '../../sales/domain/sale_models.dart';
import '../application/sabi_providers.dart';
import '../data/firebase_sabi_repository.dart';
import '../domain/sabi_command.dart';
import 'widgets/sabi_thinking_indicator.dart';

class SabiSaleDraftScreen extends ConsumerStatefulWidget {
  const SabiSaleDraftScreen({
    this.initialTranscript,
    this.startWithVoice = false,
    super.key,
  });

  final String? initialTranscript;
  final bool startWithVoice;

  @override
  ConsumerState<SabiSaleDraftScreen> createState() =>
      _SabiSaleDraftScreenState();
}

class _SabiSaleDraftScreenState extends ConsumerState<SabiSaleDraftScreen> {
  final _input = TextEditingController();
  SabiCommand? _command;
  var _loading = false;
  var _holdingSpeak = false;
  String? _error;
  final _unresolved = <String>[];
  final _draftNotes = <String>[];

  @override
  void initState() {
    super.initState();
    final initial = widget.initialTranscript?.trim() ?? '';
    if (initial.isNotEmpty) {
      _input.text = initial;
      WidgetsBinding.instance.addPostFrameCallback((_) => _parse());
    }
  }

  @override
  void deactivate() {
    if (_holdingSpeak) {
      ref.read(sabiSpeechServiceProvider).cancel();
      _holdingSpeak = false;
    }
    super.deactivate();
  }

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final active = ref.watch(activeBusinessProvider).asData?.value;
    if (active is! ActiveBusinessData) {
      return Scaffold(
        appBar: AppBar(title: const Text('Sabi sale draft')),
        body: const AppEmptyState(
          title: 'No active business',
          description: 'Set up or select a business to continue.',
          icon: Icons.storefront_outlined,
        ),
      );
    }
    final business = active.business;
    final cart = ref.watch(saleCartProvider);
    final products = ref.watch(sales.saleProductsProvider(business.businessId));
    final totals = cart.totals(
      taxEnabled: business.taxEnabled,
      taxPercentage: business.taxPercentage,
    );
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(title: const Text('Sabi Sale Draft')),
      body: ListView(
        padding: EdgeInsets.fromLTRB(
          20,
          12,
          20,
          40 + MediaQuery.viewInsetsOf(context).bottom,
        ),
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        children: <Widget>[
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: context.warningTint,
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Text(
              'Draft — Not saved. Review every item before confirming.',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _input,
            minLines: 2,
            maxLines: 4,
            decoration: const InputDecoration(
              labelText: 'Speak or type a sale instruction',
              hintText: 'Sell two bags of rice and one bottle of oil',
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: <Widget>[
              Expanded(
                child: AnimatedScale(
                  scale: _holdingSpeak ? 1.06 : 1,
                  duration: const Duration(milliseconds: 180),
                  curve: Curves.easeOutCubic,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: _holdingSpeak
                          ? const <BoxShadow>[
                              BoxShadow(
                                color: Color(0x665B3DF5),
                                blurRadius: 14,
                                offset: Offset(0, 4),
                              ),
                            ]
                          : null,
                    ),
                    child: OutlinedButton.icon(
                      onPressed: _loading
                          ? null
                          : () {
                              if (_holdingSpeak) {
                                _stopHoldSpeak();
                              } else {
                                _startHoldSpeak();
                              }
                            },
                      style: OutlinedButton.styleFrom(
                        backgroundColor: _holdingSpeak
                            ? const Color(0xFF5B3DF5)
                            : null,
                        foregroundColor:
                            _holdingSpeak ? Colors.white : null,
                        side: _holdingSpeak
                            ? BorderSide.none
                            : null,
                      ),
                      icon: Icon(
                        _holdingSpeak ? Icons.mic : Icons.mic_none,
                      ),
                      label: Text(
                        _holdingSpeak ? 'Tap to stop' : 'Tap to Speak',
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: FilledButton(
                  onPressed: _loading ? null : _parse,
                  child: _loading
                      ? const SabiThinkingIndicator()
                      : const Text('Parse with Sabi'),
                ),
              ),
            ],
          ),
          // Reserve height so the hold button does not jump under the finger.
          Opacity(
            opacity: _holdingSpeak ? 1 : 0,
            child: const Padding(
              padding: EdgeInsets.only(top: 8),
              child: Text(
                'Listening… tap Speak again when you finish.',
                style: TextStyle(
                  color: Color(0xFF5B3DF5),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
          if (_error != null) ...<Widget>[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.errorContainer,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Icon(
                    Icons.error_outline,
                    size: 18,
                    color: Theme.of(context).colorScheme.onErrorContainer,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _error!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onErrorContainer,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
          if (_command?.clarifyingQuestion != null) ...<Widget>[
            const SizedBox(height: 12),
            Text(_command!.clarifyingQuestion!),
          ],
          const SizedBox(height: 16),
          Text(
            'Cart items',
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
          ),
          ...cart.items.map(
            (item) => ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(item.name),
              subtitle: Text(
                '${formatSaleQuantityLabel(quantity: item.quantity, unit: item.unit, quantityInput: item.quantityInput)} × ${formatSaleUnitPriceLabel(formattedMoney: formatCurrency(minorToMoney(item.unitPriceMinor), symbol: business.currency.symbol), unitPriceInput: item.unitPriceInput)}',
              ),
              trailing: IconButton(
                onPressed: () => ref
                    .read(saleCartProvider.notifier)
                    .removeItem(item.saleItemId),
                icon: const Icon(Icons.close),
              ),
            ),
          ),
          if (_unresolved.isNotEmpty) ...<Widget>[
            const SizedBox(height: 8),
            Text(
              'Needs attention: ${_unresolved.join(', ')}',
              style: TextStyle(
                color: isDark ? const Color(0xFFFEC84B) : const Color(0xFFB54708),
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
          if (_draftNotes.isNotEmpty) ...<Widget>[
            const SizedBox(height: 8),
            Text(
              _draftNotes.join('\n'),
              style: TextStyle(
                color: isDark ? const Color(0xFF6CE9A6) : const Color(0xFF027A48),
                fontSize: 13,
              ),
            ),
          ],
          const SizedBox(height: 12),
          Text(
            'Total ${formatCurrency(minorToMoney(totals.totalMinor), symbol: business.currency.symbol)}',
            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18),
          ),
          const SizedBox(height: 20),
          FilledButton(
            onPressed: cart.items.isEmpty || _unresolved.isNotEmpty || _loading
                ? null
                : () {
                    context.pushNamed(AppRouteNames.checkout);
                  },
            child: const Text('Review and Confirm Sale'),
          ),
          const SizedBox(height: 8),
          TextButton(
            onPressed: () {
              ref.read(saleCartProvider.notifier).clear();
              context.pop();
            },
            child: const Text('Cancel draft'),
          ),
          products.when(
            data: (_) => const SizedBox.shrink(),
            loading: () => const LinearProgressIndicator(),
            error: (_, _) => const SizedBox.shrink(),
          ),
        ],
      ),
    );
  }

  Future<void> _startHoldSpeak() async {
    if (_loading || _holdingSpeak) return;
    setState(() {
      _holdingSpeak = true;
      _error = null;
    });
    try {
      await ref.read(sabiSpeechServiceProvider).startListening(
        seedText: _input.text,
        onPartial: (partial) {
          if (!mounted || !_holdingSpeak) return;
          final current = _input.text.trim();
          if (partial.trim().isEmpty && current.isNotEmpty) return;
          if (partial.trim().length < current.length &&
              !partial.trim().toLowerCase().startsWith(current.toLowerCase()) &&
              !current.toLowerCase().startsWith(partial.trim().toLowerCase())) {
            return;
          }
          _input.text = partial;
          _input.selection = TextSelection.collapsed(offset: _input.text.length);
        },
      );
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _holdingSpeak = false;
        _error =
            'Voice input is unavailable on this device. You can type your request.';
      });
    }
  }

  Future<void> _stopHoldSpeak() async {
    if (!_holdingSpeak) return;
    setState(() => _loading = true);
    try {
      final text = await ref.read(sabiSpeechServiceProvider).stopListening();
      if (!mounted) return;
      setState(() => _holdingSpeak = false);
      if (text.isEmpty) {
        setState(() {
          _loading = false;
          _error = 'Tap Speak, talk, then tap again to stop.';
        });
        return;
      }
      _input.text = text;
      await _parse();
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _holdingSpeak = false;
        _loading = false;
        _error =
            'Voice input is unavailable on this device. You can type your request.';
      });
    }
  }

  Future<void> _parse() async {
    final active = ref.read(activeBusinessProvider).asData?.value;
    if (active is! ActiveBusinessData) return;
    final transcript = _input.text.trim();
    if (transcript.isEmpty) {
      setState(() => _error = 'Please enter or speak a clear instruction.');
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
      _unresolved.clear();
      _draftNotes.clear();
    });
    try {
      final command = await ref
          .read(sabiRepositoryProvider)
          .parseReceiptCommand(
            businessId: active.business.businessId,
            transcript: transcript,
          );
      await _applyCommand(active.business.businessId, command);
      if (!mounted) return;
      setState(() => _command = command);
    } on SabiException catch (error) {
      if (!mounted) return;
      setState(() => _error = error.message);
    } catch (_) {
      if (!mounted) return;
      setState(
        () => _error =
            'Sabi is temporarily unavailable. You can continue the sale manually.',
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _applyCommand(String businessId, SabiCommand command) async {
    final products = await ref.read(
      sales.saleProductsProvider(businessId).future,
    );
    final cart = ref.read(saleCartProvider.notifier);
    final unresolved = <String>[];
    final notes = <String>[];

    for (final item in command.items) {
      final matches = products.where((product) {
        final name = product.name.toLowerCase();
        final spoken = item.spokenName.toLowerCase();
        return name == spoken ||
            name.contains(spoken) ||
            (product.sku ?? '').toLowerCase() == spoken;
      }).toList();

      if (item.action == 'remove') {
        final existing = ref
            .read(saleCartProvider)
            .items
            .where(
              (cartItem) => cartItem.name.toLowerCase().contains(
                item.spokenName.toLowerCase(),
              ),
            )
            .toList();
        for (final cartItem in existing) {
          cart.removeItem(cartItem.saleItemId);
        }
        continue;
      }

      final qty = item.quantity <= 0 ? 1.0 : item.quantity.toDouble();
      final spokenPriceText = item.spokenUnitPriceText?.trim();
      final spokenPriceMinor = item.spokenUnitPriceMinor ??
          (spokenPriceText != null && spokenPriceText.isNotEmpty ? 0 : null);
      final hasSpokenPrice = item.hasSpokenPrice;
      final spokenUnit = item.spokenUnit?.trim();
      final quantityLabel = () {
        final recorded = item.quantityInput?.trim();
        if (recorded != null && recorded.isNotEmpty) return recorded;
        final qtyText = qty == qty.roundToDouble()
            ? '${qty.toInt()}'
            : qty.toStringAsFixed(2);
        if (spokenUnit == null || spokenUnit.isEmpty) return qtyText;
        return '$qtyText $spokenUnit';
      }();
      final priceLabel = () {
        if (spokenPriceText != null && spokenPriceText.isNotEmpty) {
          return spokenPriceText;
        }
        if (spokenPriceMinor != null) {
          return formatCurrency(minorToMoney(spokenPriceMinor));
        }
        return null;
      }();
      final unitForLine = (spokenUnit == null || spokenUnit.isEmpty)
          ? 'unit'
          : spokenUnit;

      if (matches.length == 1) {
        final product = matches.first;
        if (product.isOutOfStock && !hasSpokenPrice) {
          unresolved.add('${item.spokenName} (out of stock)');
          continue;
        }
        if (hasSpokenPrice) {
          // Prefer spoken price for this draft (custom line, no stock decrement).
          final error = cart.addCustomItem(
            name: item.spokenName,
            quantity: qty,
            unit: unitForLine == 'unit' ? product.unit : unitForLine,
            quantityInput: quantityLabel,
            unitPrice: minorToMoney(spokenPriceMinor ?? 0),
            unitPriceInput: priceLabel,
          );
          if (error != null) {
            unresolved.add('${item.spokenName} ($error)');
          } else {
            notes.add(
              '${item.spokenName}: using spoken price ${priceLabel ?? formatCurrency(minorToMoney(spokenPriceMinor ?? 0))}',
            );
          }
          continue;
        }
        cart.addProduct(product);
        final added = ref
            .read(saleCartProvider)
            .items
            .where((cartItem) => cartItem.productId == product.productId)
            .firstOrNull;
        if (added != null &&
            (qty != added.quantity ||
                spokenUnit != null ||
                item.quantityInput != null)) {
          cart.setQuantity(
            added.saleItemId,
            qty,
            unit: spokenUnit == null || spokenUnit.isEmpty
                ? product.unit
                : spokenUnit,
            quantityInput: quantityLabel,
          );
        }
      } else if (matches.isEmpty) {
        if (!hasSpokenPrice) {
          unresolved.add(
            '${item.spokenName} (tell Sabi the price, e.g. ${item.spokenName} 50 Le or paid)',
          );
          continue;
        }
        final error = cart.addCustomItem(
          name: item.spokenName,
          quantity: qty,
          unit: unitForLine,
          quantityInput: quantityLabel,
          unitPrice: minorToMoney(spokenPriceMinor ?? 0),
          unitPriceInput: priceLabel,
        );
        if (error != null) {
          unresolved.add('${item.spokenName} ($error)');
        } else {
          notes.add('${item.spokenName}: added from chat (not in inventory)');
        }
      } else {
        if (hasSpokenPrice) {
          final error = cart.addCustomItem(
            name: item.spokenName,
            quantity: qty,
            unit: unitForLine,
            quantityInput: quantityLabel,
            unitPrice: minorToMoney(spokenPriceMinor ?? 0),
            unitPriceInput: priceLabel,
          );
          if (error != null) {
            unresolved.add('${item.spokenName} ($error)');
          } else {
            notes.add(
              '${item.spokenName}: multiple catalog matches — used spoken price',
            );
          }
        } else {
          unresolved.add('${item.spokenName} (multiple matches — add a price)');
        }
      }
    }

    if (command.paymentMethod != null) {
      final method = PaymentMethod.values.firstWhere(
        (value) => value.storedValue == command.paymentMethod,
        orElse: () => PaymentMethod.cash,
      );
      cart.setPaymentMethod(method);
    }
    if (command.amountPaidMinor != null) {
      cart.setAmountReceived(minorToMoney(command.amountPaidMinor!));
    }

    setState(() {
      _unresolved
        ..clear()
        ..addAll(unresolved);
      _draftNotes
        ..clear()
        ..addAll(notes);
    });
  }
}
