import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:shared_preferences/shared_preferences.dart';

class EulaScreen extends StatefulWidget {
  final VoidCallback onAccepted;

  const EulaScreen({super.key, required this.onAccepted});

  @override
  State<EulaScreen> createState() => _EulaScreenState();
}

class _EulaScreenState extends State<EulaScreen> {
  bool _checked = false;

  Future<void> _accept() async {
    if (!_checked) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('eula_accepted', true);
    widget.onAccepted();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final bg       = isDark ? const Color(0xFF0E1116) : const Color(0xFFF4F7FB);
    final bgDeep   = isDark ? const Color(0xFF070A0E) : const Color(0xFFE8EEF6);
    final surface  = isDark ? const Color(0xFF161B22) : Colors.white;
    final surfaceAlt = isDark ? const Color(0xFF1A2030) : const Color(0xFFEEF3FA);
    final surfaceHigh = isDark ? const Color(0xFF222A36) : const Color(0xFFE2EAF4);
    final border   = isDark ? const Color(0xFF1F2733) : const Color(0xFFE2E8F0);
    final hairline = isDark ? const Color(0x1F60A5FA) : const Color(0x192563EB);
    final blue     = isDark ? const Color(0xFF3B82F6) : const Color(0xFF2563EB);
    final blueSoft = isDark ? const Color(0x2E3B82F6) : const Color(0xFFDBEAFE);
    final blueGlow = isDark ? const Color(0x593B82F6) : const Color(0x2E2563EB);
    final textColor = isDark ? Colors.white : const Color(0xFF0F172A);
    final textDim  = isDark ? const Color(0xC7FFFFFF) : const Color(0xFF475569);
    final textMore = isDark ? const Color(0x8CFFFFFF) : const Color(0xFF64748B);
    final textFaint = isDark ? const Color(0x61FFFFFF) : const Color(0xFF94A3B8);

    return Scaffold(
      backgroundColor: bgDeep,
      body: Column(
        children: [
          // ── Top brand band ───────────────────────────────────────────────────
          Container(
            color: bg,
            child: SafeArea(
              bottom: false,
              child: Container(
                padding: const EdgeInsets.fromLTRB(22, 20, 22, 14),
                decoration: BoxDecoration(
                  border: Border(bottom: BorderSide(color: hairline)),
                ),
                child: Row(
                  children: [
                    SvgPicture.asset(
                      'assets/images/logo.svg',
                      width: 40,
                      height: 40,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('BEFORE YOU START',
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 0.8,
                                color: blue,
                              )),
                          const SizedBox(height: 2),
                          Text('End User License Agreement',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w700,
                                color: textColor,
                                letterSpacing: -0.2,
                              )),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          // ── Read-carefully callout ────────────────────────────────────────────
          Container(
            color: bg,
            padding: const EdgeInsets.fromLTRB(22, 14, 22, 14),
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: blueSoft,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: hairline),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.info_outline, size: 16, color: blue),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text.rich(
                      TextSpan(
                        style: TextStyle(
                          fontSize: 12,
                          height: 1.5,
                          color: textColor,
                        ),
                        children: const [
                          TextSpan(
                            text: 'IMPORTANT — READ CAREFULLY. ',
                            style: TextStyle(fontWeight: FontWeight.w700),
                          ),
                          TextSpan(
                            text:
                                'This Agreement is a legal agreement between you ("User") '
                                'and the KitaKo development team ("Developer") for the use '
                                'of the KitaKo mobile application. By installing, copying, '
                                'or using this Application, you agree to be bound by these terms.',
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          Container(height: 1, color: hairline),

          // ── Scrollable body ──────────────────────────────────────────────────
          Expanded(
            child: ColoredBox(
              color: bgDeep,
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(22, 18, 22, 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // §1 Definitions
                    _EulaSectionWidget(n: '1', title: 'Definitions',
                        textColor: textColor, blue: blue, children: [
                      _defRow('"Application"',
                          'refers to KitaKo, an on-device, Taglish-aware multimodal image retrieval system '
                          'developed for mobile devices using Flutter (Dart) and designed to operate fully '
                          'offline without cloud services or internet connectivity.',
                          textColor, textDim),
                      _defRow('"On-Device Processing"',
                          'refers to all computation, indexing, inference, and retrieval operations that are '
                          'executed entirely on the User\'s mobile device, without transmitting any data to external servers.',
                          textColor, textDim),
                      _defRow('"Local Data"',
                          'refers to all data generated and stored locally on the User\'s device by the Application, '
                          'including but not limited to: image embeddings, Approximate Nearest Neighbor (ANN) index files, '
                          'metadata databases, thumbnail caches, and configuration files.',
                          textColor, textDim),
                      _defRow('"Gallery"',
                          'refers to the photo library on the User\'s device, accessed through the operating system\'s photo store interface.',
                          textColor, textDim),
                      _defRow('"Query"',
                          'refers to any text-based (Taglish or English) or image-based input provided by the User '
                          'to retrieve relevant images from their indexed Gallery.',
                          textColor, textDim),
                    ]),

                    // §2 License Grant
                    _EulaSectionWidget(n: '2', title: 'License Grant',
                        textColor: textColor, blue: blue, children: [
                      _para(
                          'Subject to the terms and conditions of this Agreement, the Developer grants you a '
                          'limited, non-exclusive, non-transferable, revocable license to install and use the '
                          'Application on mobile devices that you own or control, solely for your personal, non-commercial purposes.',
                          textDim),
                    ]),

                    // §3 Privacy and Data Handling
                    _EulaSectionWidget(n: '3', title: 'Privacy and Data Handling',
                        textColor: textColor, blue: blue, children: [
                      _para(
                          'The privacy of your personal data is a foundational principle of KitaKo\'s design. '
                          'The Application is architected as a privacy-centered, on-device system, ensuring that '
                          'no user data is exposed to any external parties. The following provisions govern how '
                          'the Application handles your data:',
                          textDim),
                      _subSection('3.1', 'On-Device Architecture', blue, textColor, textDim,
                          'All processing performed by the Application—including machine learning inference via '
                          'ONNX Runtime, text normalization, image embedding generation, ANN index construction, '
                          'and similarity-based retrieval—is executed entirely on the User\'s device. No data is '
                          'transmitted to, processed by, or stored on any remote server, cloud service, or external '
                          'infrastructure at any point during the Application\'s operation.'),
                      _subSection('3.2', 'No Data Collection', blue, textColor, textDim,
                          'KitaKo does not collect, transmit, store, share, sell, or otherwise disclose any personal '
                          'data, images, search queries, metadata, embeddings, or any other user-generated content to '
                          'the Developer or any third party. The Application contains no analytics, telemetry, '
                          'tracking, or advertising frameworks.'),
                      _subSectionWithBullets('3.3', 'Gallery Access and Photo Privacy', blue, textColor, textDim,
                          'The Application requires access to your device\'s photo gallery through the operating '
                          'system\'s photo store to perform its core retrieval functions. The following protections apply:',
                          [
                            'Photos are accessed solely for the purpose of building and querying the local image index.',
                            'Original images remain under the control of the device\'s operating system at all times. '
                            'The Application does not copy, duplicate, or relocate your original photos.',
                            'Only derived representations (embedding vectors and metadata such as file names, timestamps, '
                            'and EXIF information) are stored within the Application\'s local sandbox for retrieval purposes.',
                            'No image, thumbnail, or derived representation is ever transmitted outside the device.',
                          ]),
                      _subSectionWithBulletsAndTail('3.4', 'Local Storage of Artifacts', blue, textColor, textDim,
                          'The Application stores retrieval artifacts within the device\'s local storage sandbox. These artifacts include:',
                          [
                            'Image embedding vectors generated by the on-device vision-language encoder.',
                            'ANN index files used for fast approximate nearest neighbor search.',
                            'A local metadata database associating image identifiers with retrieval information.',
                            'Configuration files for index lifecycle management and versioning.',
                          ],
                          'These artifacts are stored exclusively on the User\'s device and are never transmitted externally. '
                          'Users may delete these artifacts at any time by clearing the Application\'s data or uninstalling the Application.'),
                      _subSection('3.5', 'Privacy-by-Design Commitment', blue, textColor, textDim,
                          'KitaKo adheres to privacy-by-design principles as described in its system architecture. '
                          'Rather than relying on access control policies or post-hoc anonymization, the Application '
                          'ensures privacy structurally through its on-device architecture. By guaranteeing that queries, '
                          'images, and embeddings remain within the device, the system minimizes external data exposure '
                          'and eliminates risks associated with network transmission and server-side storage.'),
                    ]),

                    // §4 Device Permissions
                    _EulaSectionWidget(n: '4', title: 'Device Permissions',
                        textColor: textColor, blue: blue, children: [
                      _para('To function properly, the Application may request the following device permissions:', textDim),
                      _bulletWithTerm('Photo Library / Gallery Access:', textColor, textDim,
                          'Required to read and index images for retrieval. The Application accesses images through '
                          'the operating system\'s standard photo store interface.'),
                      _bulletWithTerm('Storage Access:', textColor, textDim,
                          'Required for maintaining the local index, embeddings, metadata, and configuration files '
                          'within the Application\'s sandbox.'),
                      _para(
                          'The Application does not request permissions for camera access, microphone access, location '
                          'services, contacts, network access, or any other permissions unrelated to its core photo '
                          'retrieval functionality. You may revoke permissions at any time through your device\'s settings, '
                          'though doing so may limit the Application\'s functionality.',
                          textDim),
                    ]),

                    // §5 Intellectual Property
                    _EulaSectionWidget(n: '5', title: 'Intellectual Property',
                        textColor: textColor, blue: blue, children: [
                      _para(
                          'The Application, including but not limited to its source code, design, architecture, user '
                          'interface, machine learning models (including the fine-tuned SigLIP-2 vision-language encoder), '
                          'Taglish normalization module, and documentation, is the intellectual property of the Developer '
                          'and is protected by applicable copyright, trademark, and other intellectual property laws. '
                          'This Agreement does not grant you any ownership rights in the Application.',
                          textDim),
                      _para(
                          'The training dataset utilized in the development of the Application\'s machine learning models '
                          'was curated from sources with compliant licensing. The dataset and its associated metadata, '
                          'attribution, and license information are documented for auditability and lawful reuse in '
                          'accordance with applicable data governance principles.',
                          textDim),
                    ]),

                    // §6 Restrictions
                    _EulaSectionWidget(n: '6', title: 'Restrictions',
                        textColor: textColor, blue: blue, children: [
                      _para('You agree not to:', textDim),
                      _bullet('Reverse-engineer, decompile, disassemble, or otherwise attempt to derive the source code '
                          'of the Application, except to the extent that such restriction is expressly prohibited by applicable law.',
                          textDim),
                      _bullet('Modify, adapt, translate, or create derivative works based on the Application.', textDim),
                      _bullet('Distribute, sublicense, lease, rent, loan, or otherwise transfer the Application to any third party.', textDim),
                      _bullet('Use the Application for any unlawful purpose or in violation of any applicable laws or regulations.', textDim),
                      _bullet('Attempt to bypass, disable, or interfere with any security features of the Application.', textDim),
                      _bullet('Extract, export, or attempt to access the underlying machine learning models, embedding weights, '
                          'or ANN index structures for use outside the Application.',
                          textDim),
                    ]),

                    // §7 Disclaimer of Warranties
                    _EulaSectionWidget(n: '7', title: 'Disclaimer of Warranties',
                        textColor: textColor, blue: blue, children: [
                      _para(
                          'THE APPLICATION IS PROVIDED "AS IS" AND "AS AVAILABLE" WITHOUT WARRANTIES OF ANY KIND, '
                          'WHETHER EXPRESS, IMPLIED, OR STATUTORY, INCLUDING BUT NOT LIMITED TO THE IMPLIED WARRANTIES '
                          'OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE, AND NON-INFRINGEMENT. THE DEVELOPER '
                          'DOES NOT WARRANT THAT THE APPLICATION WILL BE UNINTERRUPTED, ERROR-FREE, SECURE, OR THAT DEFECTS WILL BE CORRECTED.',
                          textDim),
                      _para(
                          'The Developer does not guarantee the accuracy, completeness, or relevance of retrieval results '
                          'produced by the Application. Retrieval effectiveness may vary depending on device capabilities, '
                          'gallery size, image content, and query formulation.',
                          textDim),
                    ]),

                    // §8 Limitation of Liability
                    _EulaSectionWidget(n: '8', title: 'Limitation of Liability',
                        textColor: textColor, blue: blue, children: [
                      _para(
                          'TO THE MAXIMUM EXTENT PERMITTED BY APPLICABLE LAW, IN NO EVENT SHALL THE DEVELOPER BE LIABLE '
                          'FOR ANY INDIRECT, INCIDENTAL, SPECIAL, CONSEQUENTIAL, OR PUNITIVE DAMAGES, OR ANY LOSS OF DATA, '
                          'PROFITS, GOODWILL, OR OTHER INTANGIBLE LOSSES, ARISING OUT OF OR IN CONNECTION WITH YOUR USE OF '
                          'OR INABILITY TO USE THE APPLICATION, EVEN IF THE DEVELOPER HAS BEEN ADVISED OF THE POSSIBILITY OF SUCH DAMAGES.',
                          textDim),
                    ]),

                    // §9 Data Retention and Deletion
                    _EulaSectionWidget(n: '9', title: 'Data Retention and Deletion',
                        textColor: textColor, blue: blue, children: [
                      _para(
                          'Since all data generated by the Application resides exclusively on your device, you retain full '
                          'control over data retention and deletion. You may delete all Application data at any time by:',
                          textDim),
                      _bullet('Clearing the Application\'s data through your device\'s application settings.', textDim),
                      _bullet('Uninstalling the Application, which will remove all locally stored artifacts including '
                          'embeddings, index files, metadata, and cached thumbnails.',
                          textDim),
                      _para('The Developer has no access to, and therefore no ability to retain, recover, or delete, '
                          'any data stored by the Application on your device.',
                          textDim),
                    ]),

                    // §10 Children's Privacy
                    _EulaSectionWidget(n: '10', title: 'Children\'s Privacy',
                        textColor: textColor, blue: blue, children: [
                      _para(
                          'The Application is not directed at children under the age of thirteen (13). The Developer does '
                          'not knowingly collect personal information from children. Since the Application does not collect '
                          'any data from any user, no special provisions for children\'s data apply. However, parental or '
                          'guardian supervision is recommended for minors using the Application.',
                          textDim),
                    ]),

                    // §11 Updates and Modifications
                    _EulaSectionWidget(n: '11', title: 'Updates and Modifications',
                        textColor: textColor, blue: blue, children: [
                      _para(
                          'The Developer may release updates to the Application from time to time. These updates may include '
                          'bug fixes, performance improvements, or new features. Updated versions of the Application will '
                          'continue to adhere to the privacy principles outlined in this Agreement. Any material changes to '
                          'how the Application handles user data—should they ever arise—will be communicated through an updated '
                          'version of this Agreement, and continued use of the Application will constitute acceptance of any such changes.',
                          textDim),
                    ]),

                    // §12 Compliance with Applicable Laws
                    _EulaSectionWidget(n: '12', title: 'Compliance with Applicable Laws',
                        textColor: textColor, blue: blue, children: [
                      _para(
                          'The Application is designed with consideration for applicable data privacy laws, including but '
                          'not limited to the Republic Act No. 10173 (Data Privacy Act of 2012) of the Philippines. By '
                          'ensuring that no personal data is collected, transmitted, or stored externally, the Application\'s '
                          'architecture is aligned with the principles of lawful processing, transparency, proportionality, '
                          'and data minimization as prescribed by applicable privacy regulations.',
                          textDim),
                    ]),

                    // §13 Termination
                    _EulaSectionWidget(n: '13', title: 'Termination',
                        textColor: textColor, blue: blue, children: [
                      _para(
                          'This Agreement is effective until terminated. Your rights under this Agreement will terminate '
                          'automatically without notice if you fail to comply with any of its terms. Upon termination, you '
                          'shall cease all use of the Application and delete all copies of the Application from your devices. '
                          'Sections 5, 7, 8, and 14 shall survive any termination of this Agreement.',
                          textDim),
                    ]),

                    // §14 Governing Law and Dispute Resolution
                    _EulaSectionWidget(n: '14', title: 'Governing Law and Dispute Resolution',
                        textColor: textColor, blue: blue, children: [
                      _para(
                          'This Agreement shall be governed by and construed in accordance with the laws of the Republic '
                          'of the Philippines, without regard to its conflict of law provisions. Any disputes arising out '
                          'of or relating to this Agreement shall be resolved through amicable negotiation in the first '
                          'instance, and if unresolved, through the appropriate courts of competent jurisdiction in the Philippines.',
                          textDim),
                    ]),

                    // §15 Severability
                    _EulaSectionWidget(n: '15', title: 'Severability',
                        textColor: textColor, blue: blue, children: [
                      _para(
                          'If any provision of this Agreement is found to be invalid or unenforceable by a court of '
                          'competent jurisdiction, the remaining provisions shall continue in full force and effect.',
                          textDim),
                    ]),

                    // §16 Entire Agreement
                    _EulaSectionWidget(n: '16', title: 'Entire Agreement',
                        textColor: textColor, blue: blue, children: [
                      _para(
                          'This Agreement constitutes the entire agreement between you and the Developer regarding the '
                          'use of the Application and supersedes all prior or contemporaneous understandings, '
                          'communications, or agreements, whether written or oral, relating to the subject matter herein.',
                          textDim),
                    ]),

                    // §17 Contact Information
                    _EulaSectionWidget(n: '17', title: 'Contact Information',
                        textColor: textColor, blue: blue, children: [
                      _para(
                          'If you have any questions, concerns, or requests regarding this Agreement or the Application\'s '
                          'privacy practices, you may contact the Developers at:',
                          textDim),
                      const SizedBox(height: 10),
                      // Contact card
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: surfaceAlt,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: hairline),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('KITAKO DEVELOPMENT TEAM',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 0.6,
                                  color: blue,
                                )),
                            const SizedBox(height: 8),
                            for (final contact in const [
                              ('Jhezra Tolentino', 'jatolentino@fit.edu.ph'),
                              ('Amiel Josiah Acuna', 'acacuna@fit.edu.ph'),
                              ('Marcus Ceasar Austria', 'mqaustria@fit.edu.ph'),
                              ('Ric Ian Barrios', 'ribarrios@fit.edu.ph'),
                            ]) ...[
                              Text(contact.$1,
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                    color: textColor,
                                  )),
                              Text(contact.$2,
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: blue,
                                    fontFamily: 'monospace',
                                  )),
                              const SizedBox(height: 6),
                            ],
                            Container(height: 1, color: hairline),
                            const SizedBox(height: 10),
                            Text('Far Eastern University – Institute of Technology',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: textMore,
                                  height: 1.5,
                                )),
                            Text('Stochastic4',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: textMore,
                                )),
                          ],
                        ),
                      ),
                    ]),

                    // Final acknowledgment box
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: surface,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: border),
                      ),
                      child: Text(
                        'BY INSTALLING OR USING KITAKO, YOU ACKNOWLEDGE THAT YOU HAVE READ, '
                        'UNDERSTOOD, AND AGREE TO BE BOUND BY THE TERMS AND CONDITIONS OF THIS '
                        'END USER LICENSE AGREEMENT.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 11.5,
                          height: 1.5,
                          color: textColor,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 0.2,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          // ── Sticky footer ────────────────────────────────────────────────────
          Container(
            color: bg,
            child: SafeArea(
              top: false,
              child: Column(
                children: [
                  Container(height: 1, color: hairline),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(18, 12, 18, 4),
                    child: GestureDetector(
                      onTap: () => setState(() => _checked = !_checked),
                      child: Row(
                        children: [
                          AnimatedContainer(
                            duration: const Duration(milliseconds: 120),
                            width: 20,
                            height: 20,
                            decoration: BoxDecoration(
                              color: _checked ? blue : Colors.transparent,
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(
                                color: _checked ? blue : textFaint,
                                width: 1.5,
                              ),
                            ),
                            child: _checked
                                ? const Icon(Icons.check,
                                    size: 14, color: Colors.white)
                                : null,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              'I have read and agree to the Agreement.',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w500,
                                color: textColor,
                                height: 1.4,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(18, 6, 18, 0),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 160),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(14),
                        boxShadow: _checked
                            ? [
                                BoxShadow(
                                  color: blueGlow,
                                  blurRadius: 24,
                                  offset: const Offset(0, 10),
                                ),
                              ]
                            : null,
                      ),
                      child: SizedBox(
                        width: double.infinity,
                        child: FilledButton(
                          onPressed: _checked ? _accept : null,
                          style: FilledButton.styleFrom(
                            backgroundColor:
                                _checked ? blue : surfaceHigh,
                            disabledBackgroundColor: surfaceHigh,
                            foregroundColor: Colors.white,
                            disabledForegroundColor: textFaint,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14)),
                            textStyle: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.1,
                            ),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Text('Agree and continue'),
                              const SizedBox(width: 8),
                              Icon(
                                Icons.north_east,
                                size: 16,
                                color: _checked ? Colors.white : textFaint,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: () => SystemNavigator.pop(),
                    style: TextButton.styleFrom(
                      foregroundColor: textMore,
                      padding: const EdgeInsets.symmetric(vertical: 10),
                    ),
                    child: const Text('Decline and exit',
                        style: TextStyle(
                            fontSize: 13, fontWeight: FontWeight.w500)),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Section wrapper ────────────────────────────────────────────────────────────

class _EulaSectionWidget extends StatelessWidget {
  final String n;
  final String title;
  final Color textColor;
  final Color blue;
  final List<Widget> children;

  const _EulaSectionWidget({
    required this.n,
    required this.title,
    required this.textColor,
    required this.blue,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              SizedBox(
                width: 20,
                child: Text(n,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.6,
                      color: blue,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    )),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(title,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: textColor,
                      height: 1.25,
                    )),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ...children,
        ],
      ),
    );
  }
}

// ── Helper widget builders ─────────────────────────────────────────────────────

Widget _para(String text, Color color) {
  return Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Text(text,
        style: TextStyle(
          fontSize: 12.5,
          height: 1.55,
          color: color,
        )),
  );
}

Widget _defRow(String term, String definition, Color textColor, Color dimColor) {
  return Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Text.rich(
      TextSpan(
        style: TextStyle(fontSize: 12.5, height: 1.55, color: dimColor),
        children: [
          TextSpan(
              text: '$term ',
              style: TextStyle(fontWeight: FontWeight.w600, color: textColor)),
          TextSpan(text: definition),
        ],
      ),
    ),
  );
}

Widget _bullet(String text, Color color) {
  return Padding(
    padding: const EdgeInsets.only(bottom: 5, left: 4),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('• ',
            style: TextStyle(fontSize: 12.5, height: 1.5, color: color)),
        Expanded(
          child: Text(text,
              style: TextStyle(fontSize: 12.5, height: 1.5, color: color)),
        ),
      ],
    ),
  );
}

Widget _bulletWithTerm(
    String term, Color textColor, Color dimColor, String definition) {
  return Padding(
    padding: const EdgeInsets.only(bottom: 5, left: 4),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('• ',
            style: TextStyle(fontSize: 12.5, height: 1.5, color: dimColor)),
        Expanded(
          child: Text.rich(
            TextSpan(
              style: TextStyle(fontSize: 12.5, height: 1.5, color: dimColor),
              children: [
                TextSpan(
                    text: '$term ',
                    style: TextStyle(
                        fontWeight: FontWeight.w600, color: textColor)),
                TextSpan(text: definition),
              ],
            ),
          ),
        ),
      ],
    ),
  );
}

Widget _subSection(String n, String title, Color blue, Color textColor,
    Color dimColor, String body) {
  return Padding(
    padding: const EdgeInsets.only(top: 10),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Text(n,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: blue,
                  fontFeatures: const [FontFeature.tabularFigures()],
                )),
            const SizedBox(width: 6),
            Text(title,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: textColor,
                )),
          ],
        ),
        const SizedBox(height: 4),
        _para(body, dimColor),
      ],
    ),
  );
}

Widget _subSectionWithBullets(String n, String title, Color blue,
    Color textColor, Color dimColor, String body, List<String> bullets) {
  return Padding(
    padding: const EdgeInsets.only(top: 10),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Text(n,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: blue,
                  fontFeatures: const [FontFeature.tabularFigures()],
                )),
            const SizedBox(width: 6),
            Text(title,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: textColor,
                )),
          ],
        ),
        const SizedBox(height: 4),
        _para(body, dimColor),
        for (final b in bullets) _bullet(b, dimColor),
      ],
    ),
  );
}

Widget _subSectionWithBulletsAndTail(String n, String title, Color blue,
    Color textColor, Color dimColor, String body, List<String> bullets, String tail) {
  return Padding(
    padding: const EdgeInsets.only(top: 10),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Text(n,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: blue,
                  fontFeatures: const [FontFeature.tabularFigures()],
                )),
            const SizedBox(width: 6),
            Text(title,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: textColor,
                )),
          ],
        ),
        const SizedBox(height: 4),
        _para(body, dimColor),
        for (final b in bullets) _bullet(b, dimColor),
        const SizedBox(height: 4),
        _para(tail, dimColor),
      ],
    ),
  );
}
