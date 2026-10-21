import JWT
import PostgresNIO
import Vapor

extension Application {
    private struct DatabaseKey: StorageKey { typealias Value = PostgresClient }
    var db: PostgresClient {
        get { storage[DatabaseKey.self]! }
        set { storage[DatabaseKey.self] = newValue }
    }
}

/// Environment: DATABASE_URL (postgres://user:password@host/db; TLS is required with it), or
/// DATABASE_HOST, DATABASE_PORT, DATABASE_USER, DATABASE_PASSWORD, DATABASE_NAME and
/// DATABASE_TLS (1 = require); JWT_SECRET, APPLE_BUNDLE_ID, AUTH_DEV (1 = allow /v1/auth/dev).
public func configure(_ app: Application) async throws {
    let config = try Environment.get("DATABASE_URL").map(databaseConfig) ?? PostgresClient.Configuration(
        host: Environment.get("DATABASE_HOST") ?? "localhost",
        port: Environment.get("DATABASE_PORT").flatMap(Int.init) ?? 5432,
        username: Environment.get("DATABASE_USER") ?? ProcessInfo.processInfo.environment["USER"] ?? "postgres",
        password: Environment.get("DATABASE_PASSWORD"),
        database: Environment.get("DATABASE_NAME") ?? "bashi_dev",
        tls: Environment.get("DATABASE_TLS") == "1" ? .require(.makeClientConfiguration()) : .disable)
    let client = PostgresClient(configuration: config, backgroundLogger: app.logger)
    app.db = client
    let runner = Task { await client.run() }
    app.lifecycle.use(ClientStopper(task: runner))

    guard let secret = Environment.get("JWT_SECRET") ?? (app.environment == .production ? nil : "development-only-secret-not-for-production-use") else {
        fatalError("JWT_SECRET is required in production")
    }
    guard secret.utf8.count >= 32 else {
        fatalError("JWT_SECRET must be at least 32 bytes")
    }
    await app.jwt.keys.add(hmac: HMACKey(from: secret), digestAlgorithm: .sha256)
    app.jwt.apple.applicationIdentifier = Environment.get("APPLE_BUNDLE_ID")

    app.routes.defaultMaxBodySize = "1mb"
    app.get("health") { _ in "ok" }
    try await Migrations.run(client, logger: app.logger)
    try routes(app)
}

/// A hosted database's connection URL. Hosted databases are reached over the internet, so TLS
/// is always required here.
func databaseConfig(_ string: String) throws -> PostgresClient.Configuration {
    guard let url = URLComponents(string: string), ["postgres", "postgresql"].contains(url.scheme ?? ""),
          let host = url.host, !host.isEmpty, let user = url.user else {
        throw Abort(.internalServerError, reason: "DATABASE_URL must look like postgres://user:password@host/database")
    }
    let database = String(url.path.drop { $0 == "/" })
    return PostgresClient.Configuration(host: host, port: url.port ?? 5432, username: user, password: url.password,
                                        database: database.isEmpty ? nil : database, tls: .require(.makeClientConfiguration()))
}

private struct ClientStopper: LifecycleHandler {
    let task: Task<Void, Never>
    func shutdown(_ application: Application) { task.cancel() }
}

func routes(_ app: Application) throws {
    let v1 = app.grouped("v1")
    try v1.register(collection: AuthController())
    try v1.grouped(UserAuthenticator()).register(collection: SyncController())
    try v1.grouped(UserAuthenticator()).register(collection: AccountController())
}
