#include <iostream>
#include <fstream>
#include <vector>
#include <filesystem>

// #ifndef pftype
//  #define fptype double
// #endif

//Global parameter which momenta are we

struct FourMomentum {
    double p[4];
};

struct Sim_params {
    std::vector<FourMomentum> momenta;
    double matrixElement;
    int matrixElementPrecision = 0;

    void printMomenta() {
        std::cout << "Number of 4-momenta: " << momenta.size() << std::endl;
        for (size_t i = 0; i < momenta.size(); ++i) {
            const FourMomentum& momentum = momenta[i];
            std::cout << "4-Momentum " << i + 1 << ": (" << momentum.p[0] << ", "
                      << momentum.p[1] << ", " << momentum.p[2] << ", " << momentum.p[3] << ")" << std::endl;
        }
    }
};

std::vector<Sim_params> readSim_paramsFromFile(const std::string& filename) {
    std::vector<Sim_params> simParamsList;
    Sim_params currentParams;
    bool readingMomenta = false;

    std::ifstream inputFile(filename);

    if (!inputFile) {
        std::cerr << "Error: Could not open the file '" << filename << "'" << std::endl;
        return simParamsList; // Empty vector indicating an error occurred
    }

    std::string line;
    while (std::getline(inputFile, line)) {
        if (line.find("Momenta:") != std::string::npos) {
            if (!currentParams.momenta.empty()) {
                if (currentParams.matrixElementPrecision < 3) // add only the ones with poor precision
                    simParamsList.push_back(currentParams);
                currentParams.momenta.clear();
            }
            readingMomenta = true;
            continue;
        }

        if (readingMomenta) {
            if (line.find("Matrix element =") != std::string::npos) {
                if (std::sscanf(line.c_str(), "Matrix element = %lf", &currentParams.matrixElement) != 1) {
                    std::cerr << "Error: Unable to parse matrix element value from line '" << line << "'" << std::endl;
                }
            } else if (line.find("Matrix element number of sig dig =") != std::string::npos) {
                if (std::sscanf(line.c_str(), "Matrix element number of sig dig =%d", &currentParams.matrixElementPrecision) != 1) {
                    std::cerr << "Error: Unable to parse matrix element precision from line '" << line << "'" << std::endl;
                }
                readingMomenta = false;
                
            } else if (!line.empty() && line[0] != '-' && line[0] != 'M') {
                int index;
                double p[4];
                if (std::sscanf(line.c_str(), "%d %lf %lf %lf %lf", &index, &p[0], &p[1], &p[2], &p[3]) == 5) {
                    FourMomentum momentum = {p[0], p[1], p[2], p[3]};
                    currentParams.momenta.push_back(momentum);
                } else {
                    std::cerr << "Error: Unable to parse line '" << line << "'" << std::endl;
                }
            }
        }
    }

    if (!currentParams.momenta.empty()) {
        if (currentParams.matrixElementPrecision < 3) // add only the ones with poor precision
            simParamsList.push_back(currentParams);
    }

    inputFile.close();
    return simParamsList;
}

// int main() {
//     const std::string filename = "input_momenta.txt";
//     std::vector<Sim_params> simParamsList = readSim_paramsFromFile(filename);

//     // Display the extracted simulation parameters
//     for (size_t i = 0; i < simParamsList.size(); ++i) {
//         Sim_params& simParams = simParamsList[i];
//         std::cout << "Set " << i + 1 << ":" << std::endl;
//         simParams.printMomenta();
//         std::cout << "Matrix element: " << simParams.matrixElement << " GeV^-2" << std::endl;
//         std::cout << "Matrix element precision: " << simParams.matrixElementPrecision << " sig dig" << std::endl;
//         std::cout << std::endl;
//     }

//     return 0;
// }
