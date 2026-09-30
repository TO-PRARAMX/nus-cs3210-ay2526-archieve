#include <assert.h>
#include <omp.h>
#include <algorithm>
#include <iostream>
#include <optional>
#include <vector>

#include "common.h"

using std::vector;
// for debugging
using std::cout;
using std::endl;

namespace traffic_prng
{
	extern PRNG *engine;
}

// compare car


/**
 * @brief heheha
 * 
 * @param car1 
 * @param car2 
 * @return true if gey
 * @return false if not gay
 * 
 */
bool cmp_by_position(const Car &car1, const Car &car2)
{
	return car1.position < car2.position;
}

bool cmp_car(const Car &car1, const Car &car2)
{
	// prioritise lane no, then position
	if (car1.lane < car2.lane)
		return 1;
	else if (car1.lane == car2.lane)
		return car1.position < car2.position;
	else
		return 0;
}

bool cmp_car_byid(const Car &car1, const Car &car2)
{
	return (car1.id < car2.id);
}


// mergesort shenanigan

size_t SERIAL_CUTOFF = 16384;
size_t INSERTION_CUTOFF = 1024;

template <typename T, typename Compare>
static inline void insertionSort(
	typename std::vector<T>::iterator arr_begin,
	size_t range,
	Compare cmp)
{	
	auto arr_end = arr_begin + range;
	for (auto it = arr_begin+1; it < arr_end; ++it) {
		T key = std::move(*it);
		auto cur = it;
		while(cur > arr_begin && cmp(key, *(cur-1))){
			*cur = std::move(*(cur-1));
			--cur;
		}
		*cur = std::move(key);
	}
	return;
}

template <typename T, typename Compare>
void merge(
    typename std::vector<T>::iterator src_itr,
    typename std::vector<T>::iterator dst_itr,
    size_t range,
    Compare cmp)
{
    size_t mid = range / 2;
    size_t i = 0, j = mid, k = 0;

    while (i < mid && j < range) {
        if (!cmp(*(src_itr + j), *(src_itr + i)))
            *(dst_itr + k++) = std::move(*(src_itr + i++));
        else
            *(dst_itr + k++) = std::move(*(src_itr + j++));
    }
    while (i < mid)   *(dst_itr + k++) = std::move(*(src_itr + i++));
    while (j < range) *(dst_itr + k++) = std::move(*(src_itr + j++));
}

template <typename T, typename Compare>
void mergeSort(
    typename std::vector<T>::iterator src_itr,
    typename std::vector<T>::iterator dst_itr,
    size_t range,
    Compare cmp)
{
    if (range < 2) {
        if (range == 1) *dst_itr = *src_itr;
        return;
    }

    if (range <= INSERTION_CUTOFF) {
        std::copy(src_itr, src_itr + range, dst_itr);
        insertionSort<T, Compare>(dst_itr, range, cmp);
        return;
    }

    size_t mid = range / 2;

    #pragma omp taskgroup
    {
        #pragma omp task if (range > SERIAL_CUTOFF)
        mergeSort<T, Compare>(dst_itr, src_itr, mid, cmp);

        #pragma omp task if (range > SERIAL_CUTOFF)
        mergeSort<T, Compare>(dst_itr + mid, src_itr + mid, range - mid, cmp);
    }

    if (!cmp(*(src_itr + mid), *(src_itr + mid - 1))) {
        std::move(src_itr, src_itr + range, dst_itr);
        return;
    }

    merge<T, Compare>(src_itr, dst_itr, range, cmp);
}

template <typename T, typename Compare>
void mergeSort(std::vector<T> &arr, Compare cmp)
{
    if (arr.size() < 2) return;

    std::vector<T> tmp(arr);

    #pragma omp parallel
    {
        #pragma omp single nowait
        mergeSort<T, Compare>(tmp.begin(), arr.begin(), arr.size(), cmp);
    }
}

// finding next car in choosen lane

inline vector<Car>::iterator nextCar(vector<Car> *cars, vector<Car>::iterator car_itr, bool sameLane, int splitIndex)
{ // assume first splitIndex is the position of first lane 1 car
	vector<Car>::iterator next;
	if (sameLane){
		next = car_itr + 1;
		if (next == cars->end()) next = cars->begin() + splitIndex;
		else if(next->lane != car_itr->lane) next = cars->begin();
	}
	else{
		// in lane 1 
		Car key = *car_itr;
		if (car_itr->lane == 0){
			next = std::upper_bound(cars->begin() + splitIndex, cars->end(), key, cmp_by_position);
			if (next == cars->end()) next = cars->begin() + splitIndex;
		}
		// in lane 0
		else{
			next = std::upper_bound(cars->begin(), cars->begin() + splitIndex, key, cmp_by_position);
			if (next == cars->begin() + splitIndex) next = cars->begin();
		}
	}
	return next;
}

inline vector<Car>::iterator prevCar(vector<Car> *cars, vector<Car>::iterator car_itr, bool sameLane, int splitIndex)
{ // only different laneI
	// same lane
	if (sameLane){
		if (car_itr->lane == 0)
			return (car_itr == cars->begin())? (car_itr + splitIndex - 1) : (car_itr - 1);
		else
			return (car_itr == cars->begin() + splitIndex)? (cars->end() - 1) : (car_itr - 1);
	}
	// different lane
	else{
		vector<Car>::iterator next = nextCar(cars, car_itr, 0, splitIndex);
		if (car_itr->lane == 0)
			return (next == cars->begin()) ? cars->begin() + splitIndex - 1 : next - 1;
		else
			return (next == cars->begin() + splitIndex) ? cars->end() - 1 : next - 1;
	}
}

// actual assignment

void executeSimulation(Params params, std::vector<Car> cars)
{
	// ================================================================================
	// SET UP
	// ================================================================================
	std::vector<Car> cars_by_id = cars;
	std::vector<Car> tmp = cars;
	
	const auto [n, L, vmax, p_dec, p_start, steps, init_file, seed] = params;


	// get initial pivot between cars in lane 0 and lane 1
	int splitIndex = 0;
	#pragma omp parallel for reduction(+ : splitIndex)
	for (int i = 0; i < n; i++)
	{
		if (!cars[i].lane)
			splitIndex++;
	}

	mergeSort(cars, cmp_car);
	

	// std::vector<u_int8_t> next_car(n,0);
	// std::vector<u_int8_t> next_car_tmp(n,0);
	// std::vector<u_int8_t> prev_car(n,0);
	// std::vector<u_int8_t> prev_car_tmp(n,0);
	std::vector<u_int8_t> previousStep_slowStart(n, 0);
	std::vector<u_int8_t> start(n, 0);
	std::vector<u_int8_t> decelerate(n, 0);
	std::vector<u_int8_t> skipStepTwo(n, 0);
	std::vector<u_int8_t> skipStepThree(n,0);

	// ================================================================================
	// RUNNING
	// ================================================================================
	for (int timestep = 0; timestep < params.steps; ++timestep)
	{
		// ----------------------------------------------------------------------------
		// Lane switching
		
		#pragma omp parallel for
		for (int i = 0; i < n; ++i){
			tmp[i] = cars[i];
		}
		int indexChange = 0;
		int laneSwitch_cnt = 0;
		#pragma omp parallel for reduction(+:indexChange,laneSwitch_cnt)
		for (int i = 0; i < n; i++){
			auto car_next_samelane = nextCar(&cars, cars.begin() + i, 1, splitIndex);
			auto car_next_difflane = nextCar(&cars, cars.begin() + i, 0, splitIndex);
			auto car_prev_difflane = prevCar(&cars, car_next_difflane, 1, splitIndex);

			int d2 = (car_next_samelane->position - cars[i].position + L) % L;
			int d3 = (car_next_difflane->position - cars[i].position + L) % L;
			int v0 = car_prev_difflane->v;
			int d0 = (cars[i].position - car_prev_difflane->position + L) % L;

			if(car_next_samelane->id == cars[i].id) {
				d2 = L;
			}

			// conditions to NOT switch lane
			if (d2 >= d3) continue;
			if (cars[i].v < d2) continue;
			if (car_prev_difflane->position == cars[i].position) continue;
			if (v0 >= d0) continue;

			// switch lane
			tmp[i].lane = 1-(cars[i].lane);
			laneSwitch_cnt++;
			if(tmp[i].lane) indexChange--;
			else indexChange++;
		}
		splitIndex += indexChange;

		// sorting
		
		if(laneSwitch_cnt != 0) mergeSort(tmp, cmp_car);
		std::swap(cars, tmp); //correct array is in cars now
		// ----------------------------------------------------------------------------

		int eachThreadWillDealWith = 0;
		int numOfThread = 0;
		
		#pragma omp parallel 
		{
			#pragma omp single
			{
				numOfThread = omp_get_num_threads();
				eachThreadWillDealWith = n / numOfThread; //so like 1100 / 8 = 137.5 so 137 -> 1096, 4 remainder
			}
			#pragma omp barrier

			int myThreadID = omp_get_thread_num();
			int iWillDealStartingFrom = myThreadID * eachThreadWillDealWith; //so this gonna be like 0, 137, 274, ... , 1096
			int iWillDealWithThisAmount = eachThreadWillDealWith; //so this gonna be 137
			if(myThreadID == numOfThread - 1) { 
				iWillDealWithThisAmount += (n % numOfThread);  //if thrad id == 7, then dealWith = 137 + 4 = 141
			}

			int iHaveToSkipThisAmount = iWillDealStartingFrom * 2;
			PRNG rng = *traffic_prng::engine;
			rng.discard(iHaveToSkipThisAmount);

			for(int i = iWillDealStartingFrom; i < (iWillDealStartingFrom + iWillDealWithThisAmount); i++) {
				start[i] = flip_coin(p_start, &rng);
				decelerate[i] = flip_coin(p_dec, &rng);
			}
		}
		traffic_prng::engine->discard(n * 2);

		#pragma omp parallel for
		for (int id = 0; id < n; ++id) {
    		skipStepTwo[id] = 0;
  	  		skipStepThree[id] = 0;
			tmp[id] = cars[id];
		}


		// ----------------------------------------------------------------------------

		int rotate0 = 0, rotate1 = 0;

		#pragma omp parallel for reduction(+:rotate0, rotate1)
		for(int i = 0; i < n; i++) {
			
			Car car_next_samelane = *nextCar(&cars, cars.begin() + i, 1, splitIndex);
			int d = (car_next_samelane.position - cars[i].position + L) % L;
			if (cars[i].id == car_next_samelane.id) d = L;

			//step 1: starting thing
			if(previousStep_slowStart[cars[i].id]) {
				previousStep_slowStart[cars[i].id] = 0;
				tmp[i].v = 1;
				skipStepThree[cars[i].id] = 1;
			}
      		else {
				if(cars[i].v == 0 && d > 1) {
					if(start[cars[i].id]) {
						skipStepTwo[cars[i].id] = 1;
						skipStepThree[cars[i].id] = 0;
					}
          			else {
						previousStep_slowStart[cars[i].id] = 1;
						skipStepTwo[cars[i].id] = 1;
						skipStepThree[cars[i].id] = 1;
						continue;
					}
				}
			}
			
			// step 2: avoid crashing
			if(!skipStepTwo[cars[i].id]) {
				if(d <= tmp[i].v && (tmp[i].v < car_next_samelane.v || tmp[i].v < 2)) {
					tmp[i].v = d - 1;
					skipStepThree[cars[i].id] = 1;
				} else if(d <= tmp[i].v && tmp[i].v >= car_next_samelane.v && tmp[i].v >= 2) {
					tmp[i].v = std::min(d - 1, tmp[i].v - 2);
					skipStepThree[cars[i].id] = 1;
				} else if(tmp[i].v < d && d <= (2 * tmp[i].v) && tmp[i].v >= car_next_samelane.v) {
					tmp[i].v = tmp[i].v - (tmp[i].v - car_next_samelane.v) / 2;
					skipStepThree[cars[i].id] = 1;
				}
			}

			// step 3: acceleration
			if(!skipStepThree[cars[i].id]) {
				if(tmp[i].v < vmax && (tmp[i].v + 1) < d) {
					tmp[i].v++;
				}
			}

			// step 4: deceleration
			if (tmp[i].v > 0 && decelerate[cars[i].id]) tmp[i].v--;

			// step 5: update position
			tmp[i].position += tmp[i].v;

			if (i < splitIndex && tmp[i].position >= L) {
				tmp[i].position -= L;
				rotate0++;
			} else if (i >= splitIndex && tmp[i].position >= L) {
				tmp[i].position -= L;
				rotate1++;
			}
		}
		
		// update actual cars vector
		// need to be parallelized (to be implemented)
		if(splitIndex > 0) std::rotate(tmp.begin(), tmp.begin()+(splitIndex-rotate0)%splitIndex, tmp.begin()+splitIndex);
		std::rotate(tmp.begin()+splitIndex, tmp.end()-rotate1, tmp.end());
		std::swap(cars, tmp);
		// ----------------------------------------------------------------------------
		
		#ifdef DEBUG
		cars_by_id = cars;
		mergeSort(cars_by_id, cmp_car_byid);
		reportResult(cars_by_id, timestep);
		#endif
	}

	mergeSort(cars, cmp_car_byid);

	// ================================================================================
	// FINAL RESULT REPORT
	// You must use this function to report the final state of the cars. (To be used for grading)
	// ================================================================================
	reportFinalResult(cars);
}
