// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/

import Foundation
import Shared
import WebKit

class WebviewViewController: UIViewController, ContentContainable, ScreenshotableView {
    private var webView: WKWebView
    var contentType: ContentType = .webview
    // Initialize PDFEmbedView
    private var pdfEmbedView: PDFEmbededView?
    var pdfUrl: URL?

    var pdfModalVC: UIViewController?

    init(webView: WKWebView, isPrivate: Bool = false) {
        self.webView = webView
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("not implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        setupWebView()
    }

    private func setupWebView() {
        pdfEmbedView = PDFEmbededView(frame: self.view.bounds)
        view.addSubview(webView)
        webView.translatesAutoresizingMaskIntoConstraints = false
        pdfEmbedView?.translatesAutoresizingMaskIntoConstraints = false // Enable Auto Layout for pdfEmbedView

        NSLayoutConstraint.activate([
            webView.topAnchor.constraint(equalTo: view.topAnchor),
            webView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            webView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            webView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
        ])
    }

    func updateVisibilityPDFView(show: Bool, url: URL?) {
        guard let url = url, let pdfEmbedView = pdfEmbedView else {
            return
        }
        self.pdfUrl = url

        pdfEmbedView.loadPDF(from: url) { result in
            switch result {
            case .success:
                print("PDF loaded successfully.")
                DispatchQueue.main.async { [unowned self] in
                    self.pdfModalVC = UIViewController()

                    guard let pdfModalVC = self.pdfModalVC else {
                        return
                    }

                    pdfModalVC.view.addSubview(pdfEmbedView)

                    NSLayoutConstraint.activate([
                        pdfEmbedView.topAnchor.constraint(equalTo: pdfModalVC.view.topAnchor),
                        pdfEmbedView.leadingAnchor.constraint(equalTo: pdfModalVC.view.leadingAnchor),
                        pdfEmbedView.bottomAnchor.constraint(equalTo: pdfModalVC.view.bottomAnchor),
                        pdfEmbedView.trailingAnchor.constraint(equalTo: pdfModalVC.view.trailingAnchor)
                    ])

                    pdfModalVC.modalPresentationStyle = .pageSheet // Swipe to dismiss

                    // left buttons
                    let closeButton = UIBarButtonItem(barButtonSystemItem: .close, target: self, action: #selector(self.dismissModal))

                    // right buttons
                    var shareButton: UIBarButtonItem?
                    var printButton: UIBarButtonItem?
                    // share button using SF Symbols
                    if let shareImage = UIImage(systemName: "square.and.arrow.up") {
                        shareButton = UIBarButtonItem(image: shareImage, style: .plain, target: self, action: #selector(self.sharePDF))
                    }

                    // print button using SF Symbols
                    if let printImage = UIImage(systemName: "printer") {
                        printButton = UIBarButtonItem(image: printImage, style: .plain, target: self, action: #selector(self.printPDF))
                    }

                    // Set the left and right bar button items
                    pdfModalVC.navigationItem.leftBarButtonItems = [closeButton]
                    if let shareButton = shareButton, let printButton = printButton {
                        pdfModalVC.navigationItem.rightBarButtonItems = [shareButton, printButton]
                    }

                    let navController = UINavigationController(rootViewController: pdfModalVC)
                    self.present(navController, animated: true, completion: nil)
                }
            case .failure(let error):
                print("Failed to load PDF: \(error)")
            }
        }
    }

    @objc 
    func dismissModal() {
        self.dismiss(animated: true, completion: nil)
    }

    // Share PDF: This doesn't necessariliy need PDF Kit
    @objc
    public func sharePDF() {
        guard let url = pdfUrl else { return }
        let activityViewController = UIActivityViewController(activityItems: [url], applicationActivities: nil)

        // Dismiss the current presented view controller, if any
        if let presented = self.presentedViewController {
            presented.dismiss(animated: true) { [weak self] in
                // Present the new view controller
                self?.present(activityViewController, animated: true, completion: nil)
            }
        } else {
            // If nothing is being presented, present the new view controller
            self.present(activityViewController, animated: true, completion: nil)
        }
    }

    // Print PDF: This doesn't necessariliy need PDF Kit
    @objc
    public func printPDF() {
        guard let url = pdfUrl else { return }

        // Asynchronously fetch PDF data
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let pdfData = try Data(contentsOf: url)
                DispatchQueue.main.async {
                    let printInfo = UIPrintInfo(dictionary: nil)
                    printInfo.jobName = url.lastPathComponent
                    printInfo.outputType = .general

                    let printController = UIPrintInteractionController.shared
                    printController.printInfo = printInfo
                    printController.printingItem = pdfData
                    printController.present(animated: true, completionHandler: nil)
                }
            } catch {
                print("Failed to fetch PDF for printing: \(error)")
            }
        }
    }

    func update(webView: WKWebView, isPrivate: Bool = false) {
        self.webView = webView
        setupWebView()
    }

    // MARK: - ScreenshotableView

    func getScreenshotData(completionHandler: @escaping (ScreenshotData?) -> Void) {
        guard let url = webView.url,
              InternalURL(url) == nil else {
            completionHandler(nil)
            return
        }

        var rect = webView.scrollView.frame
        rect.origin.x = webView.scrollView.contentOffset.x
        rect.origin.y = webView.scrollView.contentSize.height - rect.height - webView.scrollView.contentOffset.y

        webView.createPDF { result in
            switch result {
            case .success(let data):
                completionHandler(ScreenshotData(pdfData: data, rect: rect))
            case .failure:
                completionHandler(nil)
            }
        }
    }
}
