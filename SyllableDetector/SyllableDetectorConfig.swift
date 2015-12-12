//
//  SyllableDetectorConfig.swift
//  SongDetector
//
//  Created by Nathan Perkins on 9/22/15.
//  Copyright © 2015 Gardner Lab. All rights reserved.
//

import Foundation

struct SyllableDetectorConfig
{
    enum Scaling {
        case Linear
        case Log
        case Db
        
        init?(fromName name: String) {
            switch name {
            case "linear":
                self = .Linear
            case "log":
                self = .Log
            case "db":
                self = .Db
            default:
                return nil
            }
        }
    }
    
    var samplingRate: Double // eqv: samplerate
    var windowLength: Int
    var fourierLength: Int // eqv: FFT_SIZE
    var fourierOverlap: Int // eqv: NOVERLAP = FFT_SIZE - (floor(samplerate * FFT_TIME_SHIFT))
    
    let freqRange: (Double, Double) // eqv: freq_range
    let timeRange: Int // eqv: time_window_steps = double(floor(time_window / timestep))
    
    let spectrogramScaling: Scaling
    
    let threshold: Double // eqv: trigger threshold
    
    let net: NeuralNet
    
    mutating func modifySamplingRate(newSamplingRate: Double) {
        // store old things
        let oldSamplingRate = samplingRate
        let oldFourierLength = fourierLength
        let oldFourierOverlap = fourierOverlap
        
        if oldSamplingRate == newSamplingRate { return }
        
        
        // get new approximate fourier length
        let newApproximateFourierLength = newSamplingRate * Double(oldFourierLength) / oldSamplingRate
        
        // convert to closest power of 2
        let newFourierLength = 1 << Int(round(log2(newApproximateFourierLength)))
        
        // get new fourier overlap
        let newFourierOverlap = newFourierLength - Int(round(newSamplingRate * Double(oldFourierLength - oldFourierOverlap) / oldSamplingRate))
        
        // change the to new things
        samplingRate = newSamplingRate
        fourierLength = newFourierLength
        fourierOverlap = newFourierOverlap
        
        DLog("New fourier length: \(newFourierLength)")
        DLog("New fourier overlap: \(newFourierOverlap)")
    }
}

// make parsable
extension SyllableDetectorConfig
{
    enum ParseError: ErrorType {
        case UnableToOpenPath(String)
        case MissingValue(String)
        case InvalidValue(String)
        case MismatchedLength(String)
    }
    
    private static func parseString(nm: String, from data: [String: String]) throws -> String {
        guard let v = data[nm] else { throw ParseError.MissingValue(nm) }
        return v
    }
    
    private static func parseDouble(nm: String, from data: [String: String]) throws -> Double {
        guard let v = data[nm] else { throw ParseError.MissingValue(nm) }
        guard let d = Double(v) else { throw ParseError.InvalidValue(nm) }
        return d
    }
    
    private static func parseFloat(nm: String, from data: [String: String]) throws -> Float {
        guard let v = data[nm] else { throw ParseError.MissingValue(nm) }
        guard let f = Float(v) else { throw ParseError.InvalidValue(nm) }
        return f
    }
    
    private static func parseInt(nm: String, from data: [String: String]) throws -> Int {
        guard let v = data[nm] else { throw ParseError.MissingValue(nm) }
        guard let i = Int(v) else { throw ParseError.InvalidValue(nm) }
        return i
    }
    
    private static func parseDoubleArray(nm: String, withCount cnt: Int, from data: [String: String]) throws -> [Double] {
        guard let v = data[nm] else { throw ParseError.MissingValue(nm) }
        
        // split into doubles
        let stringParts = v.splitAtCharacter(",").map { $0.trim() }
        let doubleParts = stringParts.flatMap(Double.init)
        
        // compare lengths to make sure all doubles were parsed
        if stringParts.count != doubleParts.count { throw ParseError.InvalidValue(nm) }
        
        // check count
        if doubleParts.count != cnt { throw ParseError.MismatchedLength(nm) }
        
        return doubleParts
    }
    
    private static func parseFloatArray(nm: String, withCount cnt: Int, from data: [String: String]) throws -> [Float] {
        guard let v = data[nm] else { throw ParseError.MissingValue(nm) }
        
        // split into doubles
        let stringParts = v.splitAtCharacter(",").map { $0.trim() }
        let floatParts = stringParts.flatMap(Float.init)
        
        // compare lengths to make sure all doubles were parsed
        if stringParts.count != floatParts.count { throw ParseError.InvalidValue(nm) }
        
        // check count
        if floatParts.count != cnt { throw ParseError.MismatchedLength(nm) }
        
        return floatParts
    }
    
    private static func parseMapMinMax(nm: String, withCount cnt: Int, from data: [String: String]) throws -> MapMinMax {
        let xOffsets = try SyllableDetectorConfig.parseFloatArray("\(nm).xOffsets", withCount: cnt, from: data)
        let gains = try SyllableDetectorConfig.parseFloatArray("\(nm).gains", withCount: cnt, from: data)
        let yMin = try SyllableDetectorConfig.parseFloat("\(nm).yMin", from: data)
        return MapMinMax(xOffsets: xOffsets, gains: gains, yMin: yMin)
    }
    
    private static func parseMapStd(nm: String, withCount cnt: Int, from data: [String: String]) throws -> MapStd {
        let xOffsets = try SyllableDetectorConfig.parseFloatArray("\(nm).xOffsets", withCount: cnt, from: data)
        let gains = try SyllableDetectorConfig.parseFloatArray("\(nm).gains", withCount: cnt, from: data)
        let yMean = try SyllableDetectorConfig.parseFloat("\(nm).yMean", from: data)
        return MapStd(xOffsets: xOffsets, gains: gains, yMean: yMean)
    }
    
    private static func parseInputProcessingFunction(nm: String, withCount cnt: Int, from data: [String: String]) throws -> InputProcessingFunction {
        // get processing function
        // TODO: add a default processing function that passes through values
        let functionName = try SyllableDetectorConfig.parseString("\(nm).function", from: data)
        
        switch functionName {
        case "mapminmax":
            return try SyllableDetectorConfig.parseMapMinMax(nm, withCount: cnt, from: data)
            
        case "mapstd":
            return try SyllableDetectorConfig.parseMapStd(nm, withCount: cnt, from: data)
            
        case "normalize":
            return Normalize()
            
        case "normalizestd":
            return NormalizeStd()
            
        default:
            throw ParseError.InvalidValue("\(nm).function")
        }
    }
    
    private static func parseOutputProcessingFunction(nm: String, withCount cnt: Int, from data: [String: String]) throws -> OutputProcessingFunction {
        // get processing function
        let functionName = try SyllableDetectorConfig.parseString("\(nm).function", from: data)
        
        switch functionName {
        case "mapminmax":
            return try SyllableDetectorConfig.parseMapMinMax(nm, withCount: cnt, from: data)
            
        case "mapstd":
            return try SyllableDetectorConfig.parseMapStd(nm, withCount: cnt, from: data)
            
        default:
            throw ParseError.InvalidValue("\(nm).function")
        }
    }
    
    init(fromTextFile path: String) throws {
        // get stream
        guard let stream = StreamReader(path: path) else {
            throw ParseError.UnableToOpenPath(path)
        }
        
        // automatically close
        defer {
            stream.close()
        }
        
        // read line
        var data = [String: String]()
        for line in stream {
            // split string into parts
            let parts = line.splitAtCharacter("=")
            if 2 == parts.count {
                data[parts[0].trim()] = parts[1].trim()
            }
        }
        
        // read data
        // THIS SHOULD ALL BE REWRITTEN IN SOME SORT OF SYSTEMETIZED
        
        // sampling rate: double
        samplingRate = try SyllableDetectorConfig.parseDouble("samplingRate", from: data)
        
        // fourier length: int
        fourierLength = try SyllableDetectorConfig.parseInt("fourierLength", from: data)
        if !fourierLength.isPowerOfTwo() {
            throw SyllableDetectorConfig.ParseError.InvalidValue("fourierLength")
        }
        
        // window length: int, defaults to fourierLength
        if nil == data["windowLength"] {
            windowLength = fourierLength
        }
        else {
            windowLength = try SyllableDetectorConfig.parseInt("windowLength", from: data)
        }
        
        // fourier length: int
        fourierOverlap = try SyllableDetectorConfig.parseInt("fourierOverlap", from: data)
        
        // frequency range: double, double
        let potentialFreqRange = try SyllableDetectorConfig.parseDoubleArray("freqRange", withCount: 2, from: data)
        if 2 != potentialFreqRange.count { throw ParseError.MismatchedLength("freqRange") }
        freqRange = (potentialFreqRange[0], potentialFreqRange[1])
        
        // time range: int
        timeRange = try SyllableDetectorConfig.parseInt("timeRange", from: data)
        
        // threshold: double
        threshold = try SyllableDetectorConfig.parseDouble("threshold", from: data)
        
        // read scaling
        if let scaling = Scaling(fromName: try SyllableDetectorConfig.parseString("scaling", from: data)) {
            spectrogramScaling = scaling
        }
        else {
            throw ParseError.InvalidValue("scaling")
        }
        
        // get layers
        let layerCount = try SyllableDetectorConfig.parseInt("layers", from: data)
        let layers = try (0..<layerCount).map {
            (i: Int) -> NeuralNetLayer in
            let inputs = try SyllableDetectorConfig.parseInt("layer\(i).inputs", from: data)
            let outputs = try SyllableDetectorConfig.parseInt("layer\(i).outputs", from: data)
            let weights = try SyllableDetectorConfig.parseFloatArray("layer\(i).weights", withCount: (inputs * outputs), from: data)
            let biases = try SyllableDetectorConfig.parseFloatArray("layer\(i).biases", withCount: outputs, from: data)
            
            // get transfer function
            let transferFunction: TransferFunction
            switch try SyllableDetectorConfig.parseString("layer\(i).transferFunction", from: data) {
            case "TanSig": transferFunction = TanSig()
            case "LogSig": transferFunction = LogSig()
            case "PureLin": transferFunction = PureLin()
            case "SatLin": transferFunction = SatLin()
            default: throw ParseError.InvalidValue("layer\(i).transferFunction")
            }
            
            return NeuralNetLayer(inputs: inputs, weights: weights, biases: biases, outputs: outputs, transferFunction: transferFunction)
        }
        
        // get input mapping
        let processInputCount = try SyllableDetectorConfig.parseInt("processInputsCount", from: data)
        let processInputs = try (0..<processInputCount).map {
            (i: Int) -> InputProcessingFunction in
            return try SyllableDetectorConfig.parseInputProcessingFunction("processInputs\(i)", withCount: layers[0].inputs, from: data)
        }
        
        // get output mapping
        let processOutputCount = try SyllableDetectorConfig.parseInt("processOutputsCount", from: data)
        let processOutputs = try (0..<processOutputCount).map {
            (i: Int) -> OutputProcessingFunction in
            return try SyllableDetectorConfig.parseOutputProcessingFunction("processOutputs\(i)", withCount: layers[layerCount - 1].outputs, from: data)
        }
        
        // create network
        net = NeuralNet(layers: layers, inputProcessing: processInputs, outputProcessing: processOutputs)
    }
}
