// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/

import Foundation
import UIKit
import PDFKit

class PDFEmbededView: UIView, UIDocumentPickerDelegate {
    // PDFView instance
    private var pdfView: PDFView = .build { _ in }

    // PDF URL
    var pdfURL: URL?

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupUI()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupUI()
    }

    private func setupUI() {
        self.addSubview(pdfView)
        NSLayoutConstraint.activate([
            pdfView.topAnchor.constraint(equalTo: self.topAnchor),
            pdfView.leadingAnchor.constraint(equalTo: self.leadingAnchor),
            pdfView.bottomAnchor.constraint(equalTo: self.bottomAnchor),
            pdfView.trailingAnchor.constraint(equalTo: self.trailingAnchor)
        ])
    }

    // Load PDF from URL
    func loadPDF(from url: URL, completion: @escaping (Result<Void, Error>) -> Void) {
        if url.scheme == "http" || url.scheme == "https" {
            URLSession.shared.dataTask(with: url) { (data, response, error) in
                if let error = error {
                    DispatchQueue.main.async {
                        completion(.failure(error))
                    }
                    return
                }
                if let data = data, let pdfDocument = PDFDocument(data: data) {
                    DispatchQueue.main.async {
                        self.pdfView.document = pdfDocument
                        self.pdfURL = url
                        completion(.success(()))
                    }
                } else {
                    DispatchQueue.main.async {
                        completion(.failure(NSError(domain: "loading error", code: -1, userInfo: ["message": "Failed to create pdf"])))
                    }
                }
            }.resume()
        } else {
            if let pdfDocument = PDFDocument(url: url) {
                self.pdfView.document = pdfDocument
                self.pdfURL = url
                completion(.success(()))
            } else {
                completion(.failure(NSError(domain: "loading error", code: -1, userInfo: ["message": "Failed to load pdf"])))
            }
        }
    }
}
