#include <algorithm>
#include <array>
#include <chrono>
#include <cmath>
#include <cstdint>
#include <fstream>
#include <iostream>
#include <limits>
#include <numeric>
#include <random>
#include <set>
#include <sstream>
#include <string>
#include <vector>

// Dependency-free stochastic/variable-neighborhood search.  The JSON parser
// intentionally extracts only the 361 matrix integers following "matrix".

static constexpr int N = 19;
using Perm = std::array<int, N>;
using Mat = std::array<std::array<int64_t, N>, N>;

struct State {
  Perm rows{}, cols{};
  int64_t d1 = 0, d2 = 0;  // residuals divided by two
};

static uint64_t score(int64_t x, int64_t y) {
  const uint64_t ax = static_cast<uint64_t>(std::llabs(x));
  const uint64_t ay = static_cast<uint64_t>(std::llabs(y));
  // Squared L2 balances both exact equations. Tie-break with L1.
  return ax * ax + ay * ay;
}

static Mat parse_matrix(const std::string& path) {
  std::ifstream f(path);
  if (!f) throw std::runtime_error("cannot open input");
  std::string s((std::istreambuf_iterator<char>(f)), {});
  auto p = s.find("\"matrix\"");
  if (p == std::string::npos) throw std::runtime_error("matrix key missing");
  p = s.find('[', p);
  Mat a{};
  int count = 0;
  while (p < s.size() && count < N * N) {
    while (p < s.size() && !(s[p] >= '0' && s[p] <= '9')) ++p;
    if (p == s.size()) break;
    int64_t x = 0;
    while (p < s.size() && s[p] >= '0' && s[p] <= '9') x = x * 10 + (s[p++] - '0');
    a[count / N][count % N] = x;
    ++count;
  }
  if (count != N * N) throw std::runtime_error("wrong matrix element count");
  return a;
}

static std::pair<int64_t, int64_t> residuals(const Mat& w, const State& s) {
  int64_t x = 0, y = 0;
  for (int i = 0; i < N; ++i) {
    x += w[s.rows[i]][s.cols[i]];
    y += w[s.rows[i]][s.cols[N - 1 - i]];
  }
  return {x, y};
}

static std::pair<int64_t, int64_t> row_swap_delta(const Mat& w, const State& s, int a, int b) {
  const int ra = s.rows[a], rb = s.rows[b];
  int64_t x = w[rb][s.cols[a]] + w[ra][s.cols[b]]
            - w[ra][s.cols[a]] - w[rb][s.cols[b]];
  int64_t y = w[rb][s.cols[N - 1 - a]] + w[ra][s.cols[N - 1 - b]]
            - w[ra][s.cols[N - 1 - a]] - w[rb][s.cols[N - 1 - b]];
  return {x, y};
}

static std::pair<int64_t, int64_t> col_swap_delta(const Mat& w, const State& s, int a, int b) {
  const int ca = s.cols[a], cb = s.cols[b];
  int64_t x = w[s.rows[a]][cb] + w[s.rows[b]][ca]
            - w[s.rows[a]][ca] - w[s.rows[b]][cb];
  const int ia = N - 1 - a, ib = N - 1 - b;
  int64_t y = w[s.rows[ia]][cb] + w[s.rows[ib]][ca]
            - w[s.rows[ia]][ca] - w[s.rows[ib]][cb];
  return {x, y};
}

static std::pair<int64_t, int64_t> combined_delta(
    const Mat& w, State& s, int ra, int rb, int ca, int cb) {
  // Only at most eight diagonal positions change.  Recompute those before and
  // after, avoiding an O(N) scan for every 2-swap candidate.
  std::array<int, 8> q{ra, rb, ca, cb, N - 1 - ca, N - 1 - cb, -1, -1};
  std::sort(q.begin(), q.end());
  int64_t old1 = 0, old2 = 0;
  for (int k = 0; k < 8; ++k) {
    if (q[k] < 0 || (k && q[k] == q[k - 1])) continue;
    int i = q[k];
    old1 += w[s.rows[i]][s.cols[i]];
    old2 += w[s.rows[i]][s.cols[N - 1 - i]];
  }
  std::swap(s.rows[ra], s.rows[rb]);
  std::swap(s.cols[ca], s.cols[cb]);
  int64_t new1 = 0, new2 = 0;
  for (int k = 0; k < 8; ++k) {
    if (q[k] < 0 || (k && q[k] == q[k - 1])) continue;
    int i = q[k];
    new1 += w[s.rows[i]][s.cols[i]];
    new2 += w[s.rows[i]][s.cols[N - 1 - i]];
  }
  std::swap(s.cols[ca], s.cols[cb]);
  std::swap(s.rows[ra], s.rows[rb]);
  return {new1 - old1, new2 - old2};
}

static void emit_solution(const Mat& a, const State& s, const std::string& path,
                          uint64_t seed, uint64_t iterations, double seconds) {
  std::ofstream o(path);
  o << "{\n  \"exact_solution\": true,\n  \"random_seed\": " << seed
    << ",\n  \"iterations\": " << iterations << ",\n  \"elapsed_seconds\": " << seconds
    << ",\n  \"row_permutation\": [";
  for (int i = 0; i < N; ++i) o << (i ? ", " : "") << s.rows[i];
  o << "],\n  \"column_permutation\": [";
  for (int i = 0; i < N; ++i) o << (i ? ", " : "") << s.cols[i];
  o << "],\n  \"matrix\": [\n";
  for (int i = 0; i < N; ++i) {
    o << "    [";
    for (int j = 0; j < N; ++j) o << (j ? ", " : "") << a[s.rows[i]][s.cols[j]];
    o << "]" << (i + 1 == N ? "\n" : ",\n");
  }
  o << "  ]\n}\n";
}

int main(int argc, char** argv) {
  if (argc < 5) {
    std::cerr << "usage: search input.json output.json seed seconds\n";
    return 2;
  }
  Mat a = parse_matrix(argv[1]);
  const std::string output = argv[2];
  const uint64_t seed = std::stoull(argv[3]);
  const double limit = std::stod(argv[4]);
  Mat w{};
  constexpr int64_t center = 10000019;
  for (int r = 0; r < N; ++r) for (int c = 0; c < N; ++c) {
    if ((a[r][c] - center) % 2) throw std::runtime_error("parity invariant failed");
    w[r][c] = (a[r][c] - center) / 2;
  }

  std::mt19937_64 rng(seed);
  State best;
  uint64_t best_score = std::numeric_limits<uint64_t>::max();
  uint64_t iterations = 0, restarts = 0, large_scans = 0, kicks = 0;
  auto began = std::chrono::steady_clock::now();
  auto elapsed = [&] {
    return std::chrono::duration<double>(std::chrono::steady_clock::now() - began).count();
  };

  while (elapsed() < limit) {
    State s;
    std::iota(s.rows.begin(), s.rows.end(), 0);
    std::iota(s.cols.begin(), s.cols.end(), 0);
    std::shuffle(s.rows.begin(), s.rows.end(), rng);
    std::shuffle(s.cols.begin(), s.cols.end(), rng);
    std::tie(s.d1, s.d2) = residuals(w, s);
    ++restarts;
    int stagnant = 0;

    while (stagnant < 80 && elapsed() < limit) {
      ++iterations;
      uint64_t cur = score(s.d1, s.d2);
      uint64_t next_score = cur;
      bool is_row = false;
      int ba = -1, bb = -1;
      int64_t bdx = 0, bdy = 0;

      // Steepest 1-transposition descent in both permutation factors.
      for (int i = 0; i < N; ++i) for (int j = i + 1; j < N; ++j) {
        auto [dx, dy] = row_swap_delta(w, s, i, j);
        uint64_t z = score(s.d1 + dx, s.d2 + dy);
        if (z < next_score || (z == next_score && (rng() & 1))) {
          next_score = z; is_row = true; ba = i; bb = j; bdx = dx; bdy = dy;
        }
        std::tie(dx, dy) = col_swap_delta(w, s, i, j);
        z = score(s.d1 + dx, s.d2 + dy);
        if (z < next_score || (z == next_score && (rng() & 1))) {
          next_score = z; is_row = false; ba = i; bb = j; bdx = dx; bdy = dy;
        }
      }
      if (ba >= 0 && next_score < cur) {
        if (is_row) std::swap(s.rows[ba], s.rows[bb]);
        else std::swap(s.cols[ba], s.cols[bb]);
        s.d1 += bdx; s.d2 += bdy; stagnant = 0;
      } else {
        // At a 1-swap local optimum, scan all 29,241 row+column swaps. This is
        // both a much larger descent neighborhood and an exact finisher.
        ++large_scans;

        // Exact-only finishers for two sequential row swaps or two sequential
        // column swaps. Overlapping swaps include every 3-cycle; disjoint swaps
        // include the 2+2 cycle type. Deltas are evaluated after the first swap,
        // so overlap interactions are exact rather than assumed additive.
        bool exact_finish = false;
        for (int a1 = 0; a1 < N && !exact_finish; ++a1) for (int b1 = a1 + 1; b1 < N && !exact_finish; ++b1) {
          auto [dx1, dy1] = row_swap_delta(w, s, a1, b1);
          std::swap(s.rows[a1], s.rows[b1]);
          for (int a2 = 0; a2 < N && !exact_finish; ++a2) for (int b2 = a2 + 1; b2 < N; ++b2) {
            auto [dx2, dy2] = row_swap_delta(w, s, a2, b2);
            if (s.d1 + dx1 + dx2 == 0 && s.d2 + dy1 + dy2 == 0) {
              std::swap(s.rows[a2], s.rows[b2]);
              s.d1 = s.d2 = 0;
              exact_finish = true;
              break;
            }
          }
          if (!exact_finish) std::swap(s.rows[a1], s.rows[b1]);
        }
        for (int a1 = 0; a1 < N && !exact_finish; ++a1) for (int b1 = a1 + 1; b1 < N && !exact_finish; ++b1) {
          auto [dx1, dy1] = col_swap_delta(w, s, a1, b1);
          std::swap(s.cols[a1], s.cols[b1]);
          for (int a2 = 0; a2 < N && !exact_finish; ++a2) for (int b2 = a2 + 1; b2 < N; ++b2) {
            auto [dx2, dy2] = col_swap_delta(w, s, a2, b2);
            if (s.d1 + dx1 + dx2 == 0 && s.d2 + dy1 + dy2 == 0) {
              std::swap(s.cols[a2], s.cols[b2]);
              s.d1 = s.d2 = 0;
              exact_finish = true;
              break;
            }
          }
          if (!exact_finish) std::swap(s.cols[a1], s.cols[b1]);
        }
        if (exact_finish) {
          auto check = residuals(w, s);
          if (check.first || check.second) throw std::runtime_error("2-swap finisher bookkeeping error");
          emit_solution(a, s, output, seed, iterations, elapsed());
          std::cout << "FOUND exact solution in " << elapsed() << " seconds\n";
          return 0;
        }

        int bra = -1, brb = -1, bca = -1, bcb = -1;
        next_score = cur;
        for (int ra = 0; ra < N; ++ra) for (int rb = ra + 1; rb < N; ++rb)
          for (int ca = 0; ca < N; ++ca) for (int cb = ca + 1; cb < N; ++cb) {
            auto [dx, dy] = combined_delta(w, s, ra, rb, ca, cb);
            uint64_t z = score(s.d1 + dx, s.d2 + dy);
            if (z < next_score) {
              next_score = z; bra = ra; brb = rb; bca = ca; bcb = cb; bdx = dx; bdy = dy;
              if (z == 0) goto found_combined;
            }
          }
found_combined:
        if (bra >= 0 && next_score < cur) {
          std::swap(s.rows[bra], s.rows[brb]);
          std::swap(s.cols[bca], s.cols[bcb]);
          s.d1 += bdx; s.d2 += bdy; stagnant = 0;
        } else {
          // Diversification kick. Four random transpositions preserve the
          // entire row/column semimagic invariant by construction.
          for (int q = 0; q < 4; ++q) {
            int i = rng() % N, j = rng() % N;
            if (i == j) j = (j + 1) % N;
            if (rng() & 1) std::swap(s.rows[i], s.rows[j]);
            else std::swap(s.cols[i], s.cols[j]);
          }
          std::tie(s.d1, s.d2) = residuals(w, s);
          ++stagnant; ++kicks;
        }
      }

      const uint64_t sc = score(s.d1, s.d2);
      if (sc < best_score) {
        best_score = sc; best = s;
        std::cerr << "best residual/2=(" << best.d1 << ',' << best.d2 << ") score="
                  << best_score << " iter=" << iterations << " t=" << elapsed() << "\n";
      }
      if (s.d1 == 0 && s.d2 == 0) {
        auto check = residuals(w, s);
        if (check.first || check.second) throw std::runtime_error("delta bookkeeping error");
        emit_solution(a, s, output, seed, iterations, elapsed());
        std::cout << "FOUND exact solution in " << elapsed() << " seconds\n";
        return 0;
      }
    }
  }
  std::ofstream o(output);
  o << "{\n  \"exact_solution\": false,\n  \"random_seed\": " << seed
    << ",\n  \"elapsed_seconds\": " << elapsed() << ",\n  \"iterations\": " << iterations
    << ",\n  \"restarts\": " << restarts << ",\n  \"large_neighborhood_scans\": " << large_scans
    << ",\n  \"kicks\": " << kicks << ",\n  \"best_residual_divided_by_2\": ["
    << best.d1 << ", " << best.d2 << "],\n  \"best_score\": " << best_score << "\n}\n";
  std::cout << "NO exact solution; best residual/2=(" << best.d1 << ',' << best.d2 << ")\n";
  return 1;
}
