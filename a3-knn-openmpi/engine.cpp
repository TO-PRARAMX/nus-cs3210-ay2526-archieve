#include <vector>
#include <mpi.h>
#include <limits>
#include <iostream>
#include <cmath>
#include <algorithm>
#include <numeric>
#include <unordered_map>
#include <cfloat>
#include <deque>
#include <queue>
#include <memory>
#include "engine.h"

constexpr int MASTER = 0;
constexpr int STRIDE = 32;

#define CHECK_MPI(call) \
    do { \
        int res = call; \
        if (res != MPI_SUCCESS) { \
            std::cerr << "MPI Error at line " << __LINE__ << ": " << res << std::endl; \
            MPI_Abort(MPI_COMM_WORLD, res); \
        } \
    } while (0)

struct DistancePair {
	double dist;
	int index;
};

// By default, we prefer smaller dist
// Tie-break rule: prefer larger index
inline bool compare_distance_pairs(const DistancePair& a, const DistancePair& b) {
	// Closest point comes first
	if (a.dist != b.dist) {
		return a.dist < b.dist;
	}
	// Tie-break: Larger index comes first
	return a.index > b.index;
}


void merge_operation(void *invec, void* outvec, int* len, MPI_Datatype* datatype) {
    int k = *len;
    DistancePair* in  = static_cast<DistancePair*>(invec);
    DistancePair* out = static_cast<DistancePair*>(outvec);
    
    static thread_local std::vector<DistancePair> scratch;
    if (scratch.size() < (size_t)k) scratch.resize(k);

    int i = 0; // index for in
    int j = 0; // index for out
    
    for (int placed = 0; placed < k; ++placed) {
        if (j >= k) {
            scratch[placed] = in[i++];
        }
        else if (i >= k) {
            scratch[placed] = out[j++];
        }
        else if (compare_distance_pairs(in[i], out[j])) {
            scratch[placed] = in[i++];
        }
        else {
            scratch[placed] = out[j++];
        }
    }
	std::copy(scratch.begin(), scratch.begin() + k, out);
}


// Represents important MPI context (and other related fields) for each process
// Example usage: ctx.rank, ctx.num_processes
// Important: must be initialized after MPI_Init
struct Context {
	// Fields that will be set during context initialization
	int rank;
	int num_processes;
	Params p;
	MPI_Datatype MPI_DISTANCE_PAIR;
	MPI_Op merge_op;

	void create_mpi_distance_pair_type() {
		int blocklengths[2] = {1, 1};
		MPI_Datatype types[2] = {MPI_DOUBLE, MPI_INT};
		MPI_Aint offsets[2];

		// Calculate memory offsets to avoid padding issues
		offsets[0] = offsetof(DistancePair, dist);
		offsets[1] = offsetof(DistancePair, index);

		MPI_Type_create_struct(2, blocklengths, offsets, types, &MPI_DISTANCE_PAIR);
		MPI_Type_commit(&MPI_DISTANCE_PAIR);
	}

	// Constructor for initializing metadata and relevant fields
	Context(Params p): p(p) {
		MPI_Comm_size(MPI_COMM_WORLD, &num_processes);
		MPI_Comm_rank(MPI_COMM_WORLD, &rank);
		create_mpi_distance_pair_type();
		MPI_Op_create(merge_operation, 0, &merge_op);
		answer.resize(STRIDE);
	}

	~Context() {
		MPI_Type_free(&MPI_DISTANCE_PAIR);
		MPI_Op_free(&merge_op);
	}
	// Fields that will be set later throughout the execution
	// Dataset context
	int num_data_local; // Including padding
	std::vector<double> dataset_local;
	// Query context
	std::vector<double> queries_attr;
	std::vector<int> queries_k;
	// Query result (local, to be merged in merge_result)
	std::vector<std::vector<DistancePair>> answer; // idx -> distance pair

	// Enforcing singleton pattern
	Context(const Context&) = delete;
	Context& operator=(const Context&) = delete;

	static std::unique_ptr<Context> instance;

	static Context& get() {
		return *instance;
	}

	static void init(Params p) {
        if (!instance) {
            instance.reset(new Context(p));
        }
    }

	static void shutdown() {
        instance.reset();
    }
};
std::unique_ptr<Context> Context::instance = nullptr;

void distribute_dataset(std::vector<DataPoint> &dataset) {
	Context& ctx = Context::get();
	std::vector<double> sendbuf;
	int sendcount;
	if (ctx.rank == MASTER) {
		// Add padding to make sendbuf divisible by ctx.num_processes
		ctx.num_data_local = ((ctx.p.num_data + ctx.num_processes - 1) / ctx.num_processes);
	}
	MPI_Request requests[4];
	// Broadcast metadata (asynchronously)
	CHECK_MPI(MPI_Ibcast(&ctx.num_data_local, 1, MPI_INT, MASTER, MPI_COMM_WORLD, &requests[0]));
	CHECK_MPI(MPI_Ibcast(&ctx.p.num_attrs, 1, MPI_INT, MASTER, MPI_COMM_WORLD, &requests[1]));
	CHECK_MPI(MPI_Ibcast(&ctx.p.num_data, 1, MPI_INT, MASTER, MPI_COMM_WORLD, &requests[2]));
	CHECK_MPI(MPI_Ibcast(&ctx.p.num_queries, 1, MPI_INT, MASTER, MPI_COMM_WORLD, &requests[3]));
	// Preparing data
	if (ctx.rank == MASTER) {
		// Flatten dataset
		sendbuf.resize(ctx.p.num_data * ctx.p.num_attrs);
		for (int i = 0; i < ctx.p.num_data; i++) {
			std::copy(dataset[i].attrs.begin(),
			          dataset[i].attrs.end(),
			          sendbuf.begin() + (i * ctx.p.num_attrs));
		}
		sendbuf.resize(ctx.num_data_local * ctx.num_processes * ctx.p.num_attrs);
	}

	// Stall asynchronous broadcast here
	CHECK_MPI(MPI_Waitall(4, requests, MPI_STATUSES_IGNORE));

	// Preparing receive
	int count = ctx.num_data_local * ctx.p.num_attrs;
	ctx.dataset_local.resize(count);
	ctx.queries_k.resize(ctx.p.num_queries);
	ctx.queries_attr.resize(ctx.p.num_queries * ctx.p.num_attrs);

	CHECK_MPI(MPI_Scatter(sendbuf.data(), count, MPI_DOUBLE,
	                      ctx.dataset_local.data(), count, MPI_DOUBLE,
	                      MASTER, MPI_COMM_WORLD
	                     ));

}

// Distribute at once
void distribute_queries(std::vector<Query> &queries) {
	Context& ctx = Context::get();
	// Flatten ctx.queries
	// distribute queries_attr and queries_k
	if (ctx.rank == MASTER) {
		for (int i = 0; i < ctx.p.num_queries; i++) {
			ctx.queries_k[i] = queries[i].k;
			std::copy(queries[i].attrs.begin(),
			          queries[i].attrs.end(), ctx.queries_attr.begin() + (i * ctx.p.num_attrs));
		}
	}
    MPI_Bcast(ctx.queries_attr.data(), ctx.p.num_attrs * ctx.p.num_queries, 
               MPI_DOUBLE, MASTER, MPI_COMM_WORLD);
    MPI_Bcast(ctx.queries_k.data(), ctx.p.num_queries, 
               MPI_INT, MASTER, MPI_COMM_WORLD);
}

void knn_local(int idx) {
	Context& ctx = Context::get();
	int start = ctx.rank * ctx.num_data_local;
	int end = std::min(start + ctx.num_data_local - 1, ctx.p.num_data - 1);
	int num_dataset = std::max(end - start + 1, 0);

	std::priority_queue<DistancePair, std::vector<DistancePair>, decltype(&compare_distance_pairs)> 
    	pq(compare_distance_pairs);

	// Actual distance calculation
	const double* query_ptr = &ctx.queries_attr[idx * ctx.p.num_attrs];

	for (int i = 0; i < num_dataset; i++) {
        const double* data_ptr = &ctx.dataset_local[i * ctx.p.num_attrs];
		double dist_sq = 0;
		// this part is vectorized
		for (int j = 0; j < ctx.p.num_attrs; j++) {
			dist_sq += (data_ptr[j] - query_ptr[j]) * (data_ptr[j] - query_ptr[j]);
		}
		DistancePair tmp = {dist_sq, i + ctx.rank * ctx.num_data_local};
		if (pq.size() < ctx.queries_k[idx]) {
            pq.push(tmp);
        } else if (compare_distance_pairs(tmp, pq.top())) {
            pq.pop();
            pq.push({dist_sq, i + start});
        }
    }
	ctx.answer[idx % STRIDE].resize(ctx.queries_k[idx]);
	int index_max_element = std::min(num_dataset, ctx.queries_k[idx]) - 1;
	int cnt = 0;
    while (!pq.empty()) {
        ctx.answer[idx % STRIDE][index_max_element - cnt] = pq.top();
        pq.pop();
		cnt++;
    }
	// Pad elements with DOUBLE_MAX
	if (num_dataset < ctx.queries_k[idx]) {
		std::fill(ctx.answer[idx % STRIDE].begin() + num_dataset, ctx.answer[idx % STRIDE].end(), DistancePair{DBL_MAX, -1});
	}
}

int get_max_key(std::unordered_map<int, int>& freqs) {
	Context& ctx = Context::get();
	int max_freq = 0, label = -1;
	for (auto i: freqs) {
		int cur_label = i.first, freq = i.second;
		if (max_freq < freq || (max_freq == freq && cur_label > label)) {
			label = cur_label;
			max_freq = freq;
		}
	}
	return label;
}

void print_result(std::vector<DataPoint> &dataset,
                  std::vector<Query> &queries, int idx) {
	Context& ctx = Context::get();
	if (ctx.rank == MASTER) {
		// After we obtain k nearest neighbor, search for label with highest frequency
		std::vector<std::pair<double, int>> result(ctx.queries_k[idx]);
		std::unordered_map<int, int> freqs;
		for (int i = 0; i < ctx.queries_k[idx]; i++) {
			if (ctx.answer[idx % STRIDE][i].index == -1) continue;
			result[i] = {ctx.answer[idx % STRIDE][i].dist, ctx.answer[idx % STRIDE][i].index};
			int cur_label = dataset[ctx.answer[idx % STRIDE][i].index].label;
			freqs[cur_label]++;
		}
		reportResult(queries[idx], result, get_max_key(freqs));
	}
}

// [start_idx, end_idx)
void knn_solver(std::vector<DataPoint> &dataset,
                  std::vector<Query> &queries, int start_idx, int end_idx) {
	Context& ctx = Context::get();
    int batch_size = end_idx - start_idx;
    std::vector<MPI_Request> requests(batch_size);
    std::deque<std::vector<DistancePair>> master_copies;
    for (int i = 0; i < batch_size; i++) {
        int current_idx = start_idx + i;
		knn_local(current_idx);
        if (ctx.rank == MASTER) {
            master_copies.push_back(ctx.answer[current_idx % STRIDE]); // require copy
            MPI_Ireduce(master_copies.back().data(), ctx.answer[current_idx % STRIDE].data(), 
                        ctx.queries_k[current_idx], ctx.MPI_DISTANCE_PAIR, 
                        ctx.merge_op, MASTER, MPI_COMM_WORLD, &requests[i]);
        } else {
            MPI_Ireduce(ctx.answer[current_idx % STRIDE].data(), NULL, 
                        ctx.queries_k[current_idx], ctx.MPI_DISTANCE_PAIR, 
                        ctx.merge_op, MASTER, MPI_COMM_WORLD, &requests[i]);
        }
    }
	for (int i = 0; i < batch_size; i++) {
		MPI_Wait(&requests[i], MPI_STATUS_IGNORE);
		print_result(dataset, queries, start_idx + i);
	}
}

void Engine::KNN(Params &p, std::vector<DataPoint> &dataset, std::vector<Query> &queries) {
	Context::init(p);
	Context& ctx = Context::get();

	distribute_dataset(dataset);
	distribute_queries(queries);

	int n = ctx.p.num_queries;
	for (int i = 0; i < n; i += STRIDE) {
		int batch_limit = std::min(i + STRIDE, n);
		knn_solver(dataset, queries, i, batch_limit);
	}

	Context::shutdown();
}
